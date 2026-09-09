import Foundation
import Observation
import AppKit

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case warning
    case permissions
    case session
    case name
    case enroll
    case password
    case done
}

@Observable
@MainActor
final class OnboardingController {
    let camera = CameraManager()
    let pipeline: FaceRecognitionPipeline
    let session: SessionController
    let store = EnrollmentStore.shared

    var step: OnboardingStep = .welcome
    var identityName = "Me"
    var replacingID: UUID?
    var password = ""
    var confirmPassword = ""
    var status = ""
    var capturedPoses: Set<EnrollmentPose> = []
    var pendingSamples: [FaceSample] = []
    var currentPose: EnrollmentPose = .center
    var liveHint = "Center your face in the frame"
    var isCapturing = false
    var errorMessage: String?

    private var captureTask: Task<Void, Never>?
    var onComplete: (() -> Void)?

    init(session: SessionController, pipeline: FaceRecognitionPipeline, replacing: FaceIdentity? = nil) {
        self.session = session
        self.pipeline = pipeline
        if let replacing {
            replacingID = replacing.id
            identityName = replacing.name
            step = .enroll
        }
    }

    var progress: Double {
        Double(step.rawValue) / Double(OnboardingStep.allCases.count - 1)
    }

    func advance() {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            enter(next)
        }
    }

    func back() {
        if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
            enter(previous)
        }
    }

    private func enter(_ next: OnboardingStep) {
        captureTask?.cancel()
        camera.stop()
        step = next
        errorMessage = nil
        switch next {
        case .enroll:
            capturedPoses.removeAll()
            pendingSamples.removeAll()
            currentPose = .center
            startEnrollmentLoop()
        default:
            break
        }
    }

    func requestPermissions() {
        session.requestAccessibility()
        Task {
            await camera.start()
            camera.stop()
            session.refreshAccessibilityStatus()
        }
    }

    func unlockSession() async {
        await session.unlockSession()
        if session.isSessionUnlocked {
            advance()
        } else {
            errorMessage = session.sessionError ?? "Touch ID is required to encrypt your face data."
        }
    }

    func startEnrollmentLoop() {
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            await self?.camera.start()
            while !Task.isCancelled {
                await self?.tickEnrollment()
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    private func tickEnrollment() async {
        guard !isCapturing, let frame = camera.currentFrame else { return }
        let pipeline = self.pipeline
        let pose = currentPose
        let result = await Task.detached(priority: .userInitiated) { () -> FaceRecognitionResult? in
            let faces = (try? FaceDetector.detectFaces(in: frame.image)) ?? []
            guard let face = FaceRecognitionPipeline.largestFace(in: faces) else { return nil }
            guard face.normalizedBoundingBox.width >= 0.16 else { return nil }
            return try? pipeline.recognize(face, in: frame.image)
        }.value

        guard let result else {
            liveHint = "Move closer and look at the camera"
            return
        }

        guard pose.matches(yaw: result.face.yaw, pitch: result.face.pitch) else {
            liveHint = pose.instruction
            return
        }

        if let quality = result.quality, quality < 0.35 {
            liveHint = "Hold still — lighting is a bit low"
            return
        }

        isCapturing = true
        pendingSamples.append(
            FaceSample(
                embedding: result.embedding,
                pose: pose.storageName,
                capturedAt: Date(),
                quality: result.quality
            )
        )
        capturedPoses.insert(pose)
        NSSound(named: "Tink")?.play()

        if let next = EnrollmentPose.allCases.first(where: { !capturedPoses.contains($0) }) {
            currentPose = next
            liveHint = next.instruction
            isCapturing = false
        } else {
            camera.stop()
            captureTask?.cancel()
            isCapturing = false
            liveHint = "All angles captured"
            do {
                _ = try store.commitEnrollment(
                    replacing: replacingID,
                    name: identityName,
                    samples: pendingSamples,
                    embedder: pipeline.embedder
                )
                if replacingID != nil {
                    finish()
                } else {
                    advance()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func savePasswordAndFinish() async {
        guard password.count >= 1 else {
            errorMessage = "Enter the password you use to log in to this Mac."
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Those passwords don’t match."
            return
        }
        do {
            try await session.savePassword(password)
            password = ""
            confirmPassword = ""
            AppSettings.shared.isFaceUnlockEnabled = true
            advance()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finish() {
        captureTask?.cancel()
        camera.stop()
        AppSettings.shared.hasCompletedOnboarding = true
        onComplete?()
    }
}
