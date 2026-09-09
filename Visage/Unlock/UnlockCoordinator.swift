import Foundation
import CoreGraphics
import Observation

@Observable
@MainActor
final class UnlockCoordinator {
    private let session: SessionController
    let lockMonitor = LockMonitor()
    let camera = CameraManager()
    let pipeline = FaceRecognitionPipeline()

    var isEnabled: Bool {
        get { AppSettings.shared.isFaceUnlockEnabled }
        set {
            let wasEnabled = AppSettings.shared.isFaceUnlockEnabled
            AppSettings.shared.isFaceUnlockEnabled = newValue
            if wasEnabled && !newValue { disarm() }
        }
    }

    var matchThreshold: Float {
        get { AppSettings.shared.matchThreshold }
        set { AppSettings.shared.matchThreshold = newValue }
    }

    private(set) var statusMessage = "Idle"
    private(set) var lastOutcome: String?

    private var hasArmedForCurrentLock = false
    private var hasAutoRetriedForCurrentLock = false
    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0
    private var lastArmedAt: ContinuousClock.Instant?
    private let rearmDebounce: Duration = .seconds(2)
    private var autoRetryTask: Task<Void, Never>?
    private let spaceKeyMonitor = SpacebarMonitor()
    private let wrongFaceStreakThreshold = 6

    private var scanWindowDuration: TimeInterval { AppSettings.shared.scanSeconds }
    private var showsUI: Bool { AppSettings.shared.showUnlockAnimation }

    init(session: SessionController) {
        self.session = session
        spaceKeyMonitor.onSpaceKeyDown = { [weak self] in self?.handleSpaceKeyPress() }
        observeLockAndWakeEvents()
    }

    private func observeLockAndWakeEvents() {
        withObservationTracking {
            _ = lockMonitor.isScreenLocked
            _ = lockMonitor.wakeEventCount
            _ = lockMonitor.isSleeping
            _ = lockMonitor.eventCount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeLockAndWakeEvents()
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.evaluateTrigger()
            }
        }
    }

    private func evaluateTrigger() {
        guard LockMonitor.isScreenActuallyLocked() else {
            hasArmedForCurrentLock = false
            hasAutoRetriedForCurrentLock = false
            disarm()
            return
        }
        guard !lockMonitor.isSleeping else { return }

        if lockMonitor.lastEvent == .wake, !isWithinRecentArmBurst {
            hasArmedForCurrentLock = false
        }
        updateSpaceMonitor()

        guard isEnabled, !hasArmedForCurrentLock else { return }
        guard let signal = requiredTrigger(for: lockMonitor.lastEvent) else { return }
        guard OverlayGeometry.preferredScreen() != nil else { return }
        guard CredentialVault.isSessionUnlocked else {
            statusMessage = "Face unlock is on, but the session is locked."
            return
        }
        guard CredentialVault.hasStoredPassword() else {
            statusMessage = "Face unlock is on, but no password is stored yet."
            return
        }

        let shouldAutoScan = AppSettings.shared.unlockTriggers.contains(signal)
        guard showsUI || shouldAutoScan else { return }

        hasArmedForCurrentLock = true
        lastArmedAt = .now
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self?.arm(autoScan: shouldAutoScan)
        }
    }

    private var isWithinRecentArmBurst: Bool {
        guard let lastArmedAt else { return false }
        return ContinuousClock.now - lastArmedAt < rearmDebounce
    }

    private func requiredTrigger(for event: LockEventKind?) -> UnlockTrigger? {
        switch event {
        case .wake: return .onWake
        case .screenLocked: return .onLock
        case .screenUnlocked, .willSleep, nil: return nil
        }
    }

    private func disarm() {
        scanTask?.cancel()
        scanTask = nil
        scanGeneration &+= 1
        autoRetryTask?.cancel()
        autoRetryTask = nil
        camera.stop()
        OverlayController.shared.disarm()
        spaceKeyMonitor.stop()
    }

    private func updateSpaceMonitor() {
        let shouldListen = isEnabled
            && AppSettings.shared.unlockTriggers.contains(.onSpace)
            && LockMonitor.isScreenActuallyLocked()
            && SpacebarMonitor.hasListenAccess()
        if shouldListen {
            spaceKeyMonitor.start()
        } else {
            spaceKeyMonitor.stop()
        }
    }

    private func handleSpaceKeyPress() {
        guard isEnabled,
              AppSettings.shared.unlockTriggers.contains(.onSpace),
              LockMonitor.isScreenActuallyLocked(),
              OverlayGeometry.preferredScreen() != nil,
              CredentialVault.isSessionUnlocked,
              CredentialVault.hasStoredPassword()
        else { return }
        guard OverlayController.shared.phase != .scanning else { return }
        guard showsUI else {
            startScanCycle()
            return
        }
        if OverlayController.shared.isArmed {
            startScanCycle()
        } else {
            Task { [weak self] in await self?.arm(autoScan: true) }
        }
    }

    private func arm(autoScan: Bool) async {
        guard LockMonitor.isScreenActuallyLocked() else { return }
        guard showsUI else {
            startScanCycle()
            return
        }
        OverlayController.shared.arm { [weak self] in
            self?.startScanCycle()
        }
        if autoScan {
            startScanCycle()
        }
    }

    private func startScanCycle() {
        scanTask?.cancel()
        scanGeneration &+= 1
        let generation = scanGeneration
        scanTask = Task { [weak self] in
            await self?.runScanCycle(generation: generation)
        }
    }

    private func runScanCycle(generation: Int) async {
        guard LockMonitor.isScreenActuallyLocked() else { return }
        await camera.start()
        guard generation == scanGeneration else { return }
        if let error = camera.errorMessage {
            statusMessage = error
            camera.stop()
            return
        }

        let showsUI = self.showsUI
        if showsUI {
            OverlayController.shared.beginScanning(timeout: scanWindowDuration)
        }
        statusMessage = "Looking for your face…"

        let outcome = await observeScanWindow(
            deadline: Date().addingTimeInterval(scanWindowDuration),
            requireOverlayScanning: showsUI
        )
        guard generation == scanGeneration else { return }
        camera.stop()

        switch outcome {
        case .matched:
            if showsUI { OverlayController.shared.finish(success: true) }
        case .consistentlyWrongFace:
            statusMessage = "Face not recognized."
            failAndMaybeRetry(showsUI: showsUI)
        case .spoofSuspected:
            statusMessage = "Couldn't confirm a live face."
            failAndMaybeRetry(showsUI: showsUI)
        case .noResolution:
            statusMessage = "No face detected."
            if showsUI {
                scheduleAutoRetryIfEnabled(after: OverlayController.shared.collapseAnimationDuration)
            } else {
                scheduleAutoRetryIfEnabled(after: .seconds(1))
            }
        }
    }

    private func failAndMaybeRetry(showsUI: Bool) {
        if showsUI {
            OverlayController.shared.finish(success: false)
            scheduleAutoRetryIfEnabled(after: OverlayController.shared.failureHoldDuration)
        } else {
            scheduleAutoRetryIfEnabled(after: .seconds(1))
        }
    }

    private func scheduleAutoRetryIfEnabled(after delay: Duration) {
        guard AppSettings.shared.autoRetryOnce, !hasAutoRetriedForCurrentLock else { return }
        hasAutoRetriedForCurrentLock = true
        autoRetryTask?.cancel()
        autoRetryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            guard LockMonitor.isScreenActuallyLocked(), self.isEnabled else { return }
            if self.showsUI {
                guard OverlayController.shared.phase == .closed else { return }
            }
            self.startScanCycle()
        }
    }

    private enum ScanOutcome {
        case matched
        case consistentlyWrongFace
        case spoofSuspected
        case noResolution
    }

    private func observeScanWindow(deadline: Date, requireOverlayScanning: Bool) async -> ScanOutcome {
        let mode = AppSettings.shared.livenessMode
        let livenessEnabled = mode != .off
        let liveness = LivenessEngine()
        liveness.modeProvider = { AppSettings.shared.livenessMode }
        var consecutiveWrongFaceFrames = 0
        var readyMatch: ScoredIdentity?
        var livenessConfirmed = mode == .off || mode == .light
        var lastFaceBoundingBox: CGRect?
        var lastProcessedFrameID: UInt64?

        while Date() < deadline, !Task.isCancelled,
              !requireOverlayScanning || OverlayController.shared.phase == .scanning {
            guard LockMonitor.isScreenActuallyLocked() else { return .noResolution }
            guard let frame = camera.currentFrame, frame.id != lastProcessedFrameID else {
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            lastProcessedFrameID = frame.id

            let pipeline = self.pipeline
            let previousBoundingBox = lastFaceBoundingBox
            let outcome = await Task.detached(priority: .userInitiated) { () -> (FaceRecognitionResult, LivenessFrame)? in
                guard let result = try? pipeline.recognize(in: frame.image, preferNear: previousBoundingBox) else { return nil }
                let faceCrop = CameraManager.renderCrop(from: frame, imageRect: result.face.boundingBox)
                return (result, LivenessFeatures.extract(from: result, frame: frame.image, faceCrop: faceCrop))
            }.value

            guard let (result, livenessFrame) = outcome else {
                consecutiveWrongFaceFrames = 0
                lastFaceBoundingBox = nil
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            lastFaceBoundingBox = result.face.normalizedBoundingBox

            if livenessEnabled {
                let snapshot = liveness.observe(livenessFrame)
                switch snapshot.decision {
                case .denied(let reason):
                    lastOutcome = reason
                    return .spoofSuspected
                case .confirmed:
                    livenessConfirmed = true
                case .pending:
                    break
                }
            }

            let scored = pipeline.score(result.embedding, against: EnrollmentStore.shared.activeIdentities)
            let matched = pipeline.bestMatch(in: scored, threshold: matchThreshold)

            if let matched {
                consecutiveWrongFaceFrames = 0
                readyMatch = matched
            } else {
                readyMatch = nil
                consecutiveWrongFaceFrames += 1
                if consecutiveWrongFaceFrames >= wrongFaceStreakThreshold {
                    return .consistentlyWrongFace
                }
            }

            if let readyMatch, livenessConfirmed {
                statusMessage = "Recognized — unlocking…"
                lastOutcome = "Matched \(readyMatch.identity.name) at \(String(format: "%.3f", readyMatch.centroidSimilarity))."
                await session.injectStoredPassword(requireAuthoritativeLock: true)
                return .matched
            }

            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return .noResolution
    }
}
