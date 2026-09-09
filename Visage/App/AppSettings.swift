import Foundation
import Observation
import ServiceManagement

enum UnlockTrigger: String, Codable, CaseIterable, Identifiable {
    case onWake
    case onLock
    case onSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onWake: return "When the display wakes"
        case .onLock: return "When the screen locks"
        case .onSpace: return "When you press Space on the lock screen"
        }
    }

    var detail: String {
        switch self {
        case .onWake: return "Lid open, display sleep ending, or screensaver dismissed."
        case .onLock: return "As soon as macOS shows the lock screen."
        case .onSpace: return "Same gesture as waking a sleeping lock screen."
        }
    }
}

enum LivenessMode: String, Codable, CaseIterable, Identifiable {
    case off
    case light
    case heavy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .light: return "Light"
        case .heavy: return "Heavy"
        }
    }

    var detail: String {
        switch self {
        case .off: return "Match the face only. Photos can succeed."
        case .light: return "Reject screen glare and obvious spoofs. A still person still unlocks."
        case .heavy: return "Also require a live cue — a blink or a small head turn."
        }
    }
}

enum AutoLockInterval: String, Codable, CaseIterable, Identifiable {
    case fifteenMinutes
    case oneHour
    case eightHours
    case oneDay
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifteenMinutes: return "15 minutes"
        case .oneHour: return "1 hour"
        case .eightHours: return "8 hours"
        case .oneDay: return "1 day"
        case .never: return "Until I lock it"
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .oneHour: return 60 * 60
        case .eightHours: return 8 * 60 * 60
        case .oneDay: return 24 * 60 * 60
        case .never: return nil
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }

    var isFaceUnlockEnabled: Bool {
        didSet { defaults.set(isFaceUnlockEnabled, forKey: Keys.enabled) }
    }

    var matchThreshold: Float {
        didSet { defaults.set(matchThreshold, forKey: Keys.threshold) }
    }

    var scanSeconds: Double {
        didSet { defaults.set(scanSeconds, forKey: Keys.scanSeconds) }
    }

    var livenessMode: LivenessMode {
        didSet { defaults.set(livenessMode.rawValue, forKey: Keys.liveness) }
    }

    var showUnlockAnimation: Bool {
        didSet { defaults.set(showUnlockAnimation, forKey: Keys.animation) }
    }

    var autoRetryOnce: Bool {
        didSet { defaults.set(autoRetryOnce, forKey: Keys.retry) }
    }

    var unlockTriggers: Set<UnlockTrigger> {
        didSet {
            defaults.set(unlockTriggers.map(\.rawValue), forKey: Keys.triggers)
        }
    }

    var autoLockInterval: AutoLockInterval {
        didSet { defaults.set(autoLockInterval.rawValue, forKey: Keys.autoLock) }
    }

    var defaultCameraID: String? {
        didSet { defaults.set(defaultCameraID, forKey: Keys.camera) }
    }

    var builtInDisplayCameraID: String? {
        didSet { defaults.set(builtInDisplayCameraID, forKey: Keys.builtInCamera) }
    }

    var externalDisplayCameraID: String? {
        didSet { defaults.set(externalDisplayCameraID, forKey: Keys.externalCamera) }
    }

    var minimumFaceWidth: Float {
        didSet {
            defaults.set(minimumFaceWidth, forKey: Keys.minFace)
            FaceRecognitionPipeline.minimumProminentFaceWidth = minimumFaceWidth
        }
    }

    private init() {
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        isFaceUnlockEnabled = defaults.bool(forKey: Keys.enabled)
        let storedThreshold = defaults.object(forKey: Keys.threshold) as? Float
        matchThreshold = storedThreshold ?? 0.38
        let storedScan = defaults.object(forKey: Keys.scanSeconds) as? Double
        scanSeconds = storedScan ?? 8
        livenessMode = LivenessMode(rawValue: defaults.string(forKey: Keys.liveness) ?? "") ?? .light
        showUnlockAnimation = defaults.object(forKey: Keys.animation) as? Bool ?? true
        autoRetryOnce = defaults.object(forKey: Keys.retry) as? Bool ?? true
        if let raw = defaults.array(forKey: Keys.triggers) as? [String] {
            unlockTriggers = Set(raw.compactMap(UnlockTrigger.init(rawValue:)))
        } else {
            unlockTriggers = [.onWake, .onSpace]
        }
        autoLockInterval = AutoLockInterval(rawValue: defaults.string(forKey: Keys.autoLock) ?? "") ?? .oneDay
        defaultCameraID = defaults.string(forKey: Keys.camera)
        builtInDisplayCameraID = defaults.string(forKey: Keys.builtInCamera)
        externalDisplayCameraID = defaults.string(forKey: Keys.externalCamera)
        let storedMin = defaults.object(forKey: Keys.minFace) as? Float
        minimumFaceWidth = storedMin ?? 0.18
        FaceRecognitionPipeline.minimumProminentFaceWidth = minimumFaceWidth
    }

    private enum Keys {
        static let onboarding = "visage.hasCompletedOnboarding"
        static let enabled = "visage.isFaceUnlockEnabled"
        static let threshold = "visage.matchThreshold"
        static let scanSeconds = "visage.scanSeconds"
        static let liveness = "visage.livenessMode"
        static let animation = "visage.showUnlockAnimation"
        static let retry = "visage.autoRetryOnce"
        static let triggers = "visage.unlockTriggers"
        static let autoLock = "visage.autoLockInterval"
        static let camera = "visage.defaultCameraID"
        static let builtInCamera = "visage.builtInDisplayCameraID"
        static let externalCamera = "visage.externalDisplayCameraID"
        static let minFace = "visage.minimumFaceWidth"
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status == .enabled else { return }
            try SMAppService.mainApp.unregister()
        }
    }
}
