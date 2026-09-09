import Foundation
import CoreGraphics
import Vision

struct LivenessFrame {
    let timestamp: Date
    let yaw: Float?
    let pitch: Float?
    let eyeAspect: CGFloat?
    let nose: CGPoint?
    let interocular: CGFloat?
    let glareRatio: Float
}

enum LivenessCue: String {
    case glare
    case blink
    case motion
}

enum LivenessDecision {
    case pending
    case confirmed(LivenessCue)
    case denied(String)

    var denialReason: String? {
        if case .denied(let reason) = self { return reason }
        return nil
    }
}

struct LivenessSnapshot {
    let decision: LivenessDecision
    let glareRatio: Float
    let confirmed: Bool

    static let empty = LivenessSnapshot(decision: .pending, glareRatio: 0, confirmed: false)
}

nonisolated enum LivenessFeatures {
    static func extract(from result: FaceRecognitionResult, frame: CGImage, faceCrop: CGImage?) -> LivenessFrame {
        let landmarks = result.face.landmarks
        let size = result.face.imageSize
        let leftEAR = landmarks.flatMap { $0.leftEye }.flatMap { LandmarkGeometry.eyeAspectRatio(of: $0, imageSize: size) }
        let rightEAR = landmarks.flatMap { $0.rightEye }.flatMap { LandmarkGeometry.eyeAspectRatio(of: $0, imageSize: size) }
        let ear: CGFloat?
        if let leftEAR, let rightEAR {
            ear = (leftEAR + rightEAR) / 2
        } else {
            ear = leftEAR ?? rightEAR
        }
        return LivenessFrame(
            timestamp: Date(),
            yaw: result.face.yaw,
            pitch: result.face.pitch,
            eyeAspect: ear,
            nose: landmarks.flatMap { LandmarkGeometry.noseCenter(from: $0, imageSize: size) },
            interocular: landmarks.flatMap { LandmarkGeometry.interocularDistance(from: $0, imageSize: size) },
            glareRatio: glareRatio(in: faceCrop ?? result.alignedImage)
        )
    }

    static func glareRatio(in image: CGImage) -> Float {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }
        let width = image.width
        let height = image.height
        let bpp = max(image.bitsPerPixel / 8, 1)
        let row = image.bytesPerRow
        var bright = 0
        var total = 0
        let step = max(1, min(width, height) / 64)
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let offset = y * row + x * bpp
                let r = Float(bytes[offset])
                let g = bpp > 1 ? Float(bytes[offset + 1]) : r
                let b = bpp > 2 ? Float(bytes[offset + 2]) : r
                let luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
                if luma > 0.93 { bright += 1 }
                total += 1
            }
        }
        guard total > 0 else { return 0 }
        return Float(bright) / Float(total)
    }
}

@MainActor
final class LivenessEngine {
    private let windowDuration: TimeInterval
    var modeProvider: () -> LivenessMode = { .light }
    private var frames: [LivenessFrame] = []
    private var confirmedCue: LivenessCue?
    private var denied: String?

    init(windowDuration: TimeInterval = 2.0) {
        self.windowDuration = windowDuration
    }

    func reset() {
        frames.removeAll()
        confirmedCue = nil
        denied = nil
    }

    @discardableResult
    func observe(_ frame: LivenessFrame) -> LivenessSnapshot {
        frames.append(frame)
        frames.removeAll { frame.timestamp.timeIntervalSince($0.timestamp) > windowDuration }
        let mode = modeProvider()

        if mode != .off, frame.glareRatio > 0.12 {
            denied = "Screen glare — that looks like a photo or display."
        }

        if mode != .off, confirmedCue == nil {
            if sawBlink() {
                confirmedCue = .blink
            } else if sawMotion() {
                confirmedCue = .motion
            }
        }

        let decision: LivenessDecision
        if let denied {
            decision = .denied(denied)
        } else if mode == .off {
            decision = .confirmed(.motion)
        } else if let confirmedCue {
            decision = .confirmed(confirmedCue)
        } else {
            decision = .pending
        }

        return LivenessSnapshot(
            decision: decision,
            glareRatio: frame.glareRatio,
            confirmed: confirmedCue != nil || mode != .heavy
        )
    }

    private func sawBlink() -> Bool {
        let values = frames.compactMap(\.eyeAspect)
        guard values.count >= 6 else { return false }
        guard let maxOpen = values.max(), let minClosed = values.min() else { return false }
        return maxOpen > 0.18 && minClosed < maxOpen * 0.55 && minClosed < 0.16
    }

    private func sawMotion() -> Bool {
        let yaws = frames.compactMap(\.yaw).map { CGFloat($0) }
        if yaws.count >= 8, let minY = yaws.min(), let maxY = yaws.max(), maxY - minY > 0.12 {
            return true
        }
        let noses = frames.compactMap(\.nose)
        let scales = frames.compactMap(\.interocular)
        guard noses.count >= 8, let scale = scales.last, scale > 1 else { return false }
        let xs = noses.map(\.x)
        let ys = noses.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return false }
        let travel = hypot(maxX - minX, maxY - minY) / scale
        return travel > 0.08
    }
}
