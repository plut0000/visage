import Foundation
import CoreGraphics

enum EnrollmentPose: Int, CaseIterable, Identifiable {
    case center, left, topLeft, top, topRight, right, bottomRight, bottom, bottomLeft

    var id: Int { rawValue }

    enum YawBand { case left, none, right }
    enum PitchBand { case up, none, down }

    var yawBand: YawBand {
        switch self {
        case .left, .topLeft, .bottomLeft: return .left
        case .right, .topRight, .bottomRight: return .right
        case .center, .top, .bottom: return .none
        }
    }

    var pitchBand: PitchBand {
        switch self {
        case .top, .topLeft, .topRight: return .up
        case .bottom, .bottomLeft, .bottomRight: return .down
        case .center, .left, .right: return .none
        }
    }

    var instruction: String {
        switch self {
        case .center: return "Look straight at the camera"
        case .left: return "Turn a little to your left"
        case .topLeft: return "Look up and left"
        case .top: return "Look slightly up"
        case .topRight: return "Look up and right"
        case .right: return "Turn a little to your right"
        case .bottomRight: return "Look down and right"
        case .bottom: return "Look slightly down"
        case .bottomLeft: return "Look down and left"
        }
    }

    var storageName: String {
        switch self {
        case .center: return "center"
        case .left: return "left"
        case .topLeft: return "top_left"
        case .top: return "top"
        case .topRight: return "top_right"
        case .right: return "right"
        case .bottomRight: return "bottom_right"
        case .bottom: return "bottom"
        case .bottomLeft: return "bottom_left"
        }
    }

    func matches(yaw: Float?, pitch: Float?) -> Bool {
        let yawValue = yaw ?? 0
        let pitchValue = pitch ?? 0
        let yawOK: Bool
        switch yawBand {
        case .left: yawOK = yawValue < -0.18
        case .right: yawOK = yawValue > 0.18
        case .none: yawOK = abs(yawValue) < 0.16
        }
        let pitchOK: Bool
        switch pitchBand {
        case .up: pitchOK = pitchValue > 0.12
        case .down: pitchOK = pitchValue < -0.12
        case .none: pitchOK = abs(pitchValue) < 0.16
        }
        return yawOK && pitchOK
    }
}
