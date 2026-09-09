import Vision
import CoreGraphics

enum LandmarkRegion: String, CaseIterable {
    case leftEye, rightEye, leftEyebrow, rightEyebrow
    case nose, noseCrest, outerLips, innerLips, faceContour, medianLine
}

struct LandmarkPoint {
    let point: CGPoint
    let region: LandmarkRegion
    let indexInRegion: Int
}

nonisolated enum LandmarkGeometry {
    static func imagePoints(of region: VNFaceLandmarkRegion2D, imageSize: CGSize) -> [CGPoint] {
        region.pointsInImage(imageSize: imageSize).map { CGPoint(x: $0.x, y: imageSize.height - $0.y) }
    }

    static func centroid(of region: VNFaceLandmarkRegion2D, imageSize: CGSize) -> CGPoint? {
        let points = imagePoints(of: region, imageSize: imageSize)
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    static func eyeCenter(pupil: VNFaceLandmarkRegion2D?, eye: VNFaceLandmarkRegion2D?, imageSize: CGSize) -> CGPoint? {
        if let pupil, let center = centroid(of: pupil, imageSize: imageSize) { return center }
        if let eye { return centroid(of: eye, imageSize: imageSize) }
        return nil
    }

    static func interocularDistance(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> CGFloat? {
        guard let left = eyeCenter(pupil: landmarks.leftPupil, eye: landmarks.leftEye, imageSize: imageSize),
              let right = eyeCenter(pupil: landmarks.rightPupil, eye: landmarks.rightEye, imageSize: imageSize)
        else { return nil }
        return hypot(left.x - right.x, left.y - right.y)
    }

    static func eyeAspectRatio(of eyeRegion: VNFaceLandmarkRegion2D, imageSize: CGSize) -> CGFloat? {
        let points = imagePoints(of: eyeRegion, imageSize: imageSize)
        guard points.count >= 3,
              let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return nil }
        let width = maxX - minX
        guard width > 0 else { return nil }
        return (maxY - minY) / width
    }

    static func region(_ region: LandmarkRegion, of landmarks: VNFaceLandmarks2D) -> VNFaceLandmarkRegion2D? {
        switch region {
        case .leftEye: return landmarks.leftEye
        case .rightEye: return landmarks.rightEye
        case .leftEyebrow: return landmarks.leftEyebrow
        case .rightEyebrow: return landmarks.rightEyebrow
        case .nose: return landmarks.nose
        case .noseCrest: return landmarks.noseCrest
        case .outerLips: return landmarks.outerLips
        case .innerLips: return landmarks.innerLips
        case .faceContour: return landmarks.faceContour
        case .medianLine: return landmarks.medianLine
        }
    }

    static func allPoints(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> [LandmarkPoint] {
        var result: [LandmarkPoint] = []
        for regionCase in LandmarkRegion.allCases {
            guard let vnRegion = region(regionCase, of: landmarks) else { continue }
            let points = imagePoints(of: vnRegion, imageSize: imageSize)
            for (index, point) in points.enumerated() {
                result.append(LandmarkPoint(point: point, region: regionCase, indexInRegion: index))
            }
        }
        return result
    }

    static func noseCenter(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> CGPoint? {
        guard let nose = landmarks.nose else { return nil }
        return centroid(of: nose, imageSize: imageSize)
    }

    /// 2D Procrustes similarity: rotation, uniform scale, translation.
    static func solveSimilarityTransform(from sourcePoints: [CGPoint], to destinationPoints: [CGPoint]) -> CGAffineTransform? {
        guard sourcePoints.count == destinationPoints.count, sourcePoints.count >= 2 else { return nil }

        let n = CGFloat(sourcePoints.count)
        let srcSum = sourcePoints.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let srcMean = CGPoint(x: srcSum.x / n, y: srcSum.y / n)
        let dstSum = destinationPoints.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let dstMean = CGPoint(x: dstSum.x / n, y: dstSum.y / n)

        var numeratorReal: CGFloat = 0
        var numeratorImag: CGFloat = 0
        var denominator: CGFloat = 0
        for i in 0..<sourcePoints.count {
            let p = CGPoint(x: sourcePoints[i].x - srcMean.x, y: sourcePoints[i].y - srcMean.y)
            let q = CGPoint(x: destinationPoints[i].x - dstMean.x, y: destinationPoints[i].y - dstMean.y)
            numeratorReal += q.x * p.x + q.y * p.y
            numeratorImag += q.y * p.x - q.x * p.y
            denominator += p.x * p.x + p.y * p.y
        }
        guard denominator > 0 else { return nil }

        let sc = numeratorReal / denominator
        let ss = numeratorImag / denominator
        let a = sc, b = ss, c = -ss, d = sc
        let tx = dstMean.x - (a * srcMean.x + c * srcMean.y)
        let ty = dstMean.y - (b * srcMean.x + d * srcMean.y)
        return CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }
}
