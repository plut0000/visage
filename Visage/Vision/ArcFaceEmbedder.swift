import CoreML
import CoreGraphics
import CoreVideo

enum ArcFaceEmbedderError: LocalizedError {
    case modelNotFound
    case modelLoadFailed(String)
    case pixelBufferCreationFailed
    case unexpectedInputSize(got: (Int, Int), expected: Int)
    case unexpectedOutput(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "ArcFace model is missing from the app bundle."
        case .modelLoadFailed(let detail):
            return "Failed to load ArcFace: \(detail)"
        case .pixelBufferCreationFailed:
            return "Couldn't prepare the aligned face for Core ML."
        case .unexpectedInputSize(let got, let expected):
            return "ArcFace expects \(expected)×\(expected), got \(got.0)×\(got.1)."
        case .unexpectedOutput(let detail):
            return "ArcFace produced an unexpected output: \(detail)"
        }
    }
}

nonisolated final class ArcFaceEmbedder: FaceEmbedder, @unchecked Sendable {
    nonisolated let name = "ArcFace (w600k_mbf)"
    nonisolated let modelIdentifier = "arcface-w600k_mbf-v1"
    nonisolated let embeddingDimension = 512
    nonisolated let requiresAlignment = true

    private static let inputSize = FaceAligner.outputSize
    private static let inputName = "input_image"
    private static let outputName = "embedding"

    private let model: MLModel
    private let pixelBufferPool: CVPixelBufferPool

    init() throws {
        guard let modelURL = Self.locateModel() else {
            throw ArcFaceEmbedderError.modelNotFound
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        do {
            model = try MLModel(contentsOf: modelURL, configuration: configuration)
        } catch {
            throw ArcFaceEmbedderError.modelLoadFailed(error.localizedDescription)
        }
        guard let pool = Self.makePixelBufferPool(size: Self.inputSize) else {
            throw ArcFaceEmbedderError.pixelBufferCreationFailed
        }
        pixelBufferPool = pool
    }

    private static func locateModel() -> URL? {
        for name in ["ArcFace", "w600k_mbf"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                return url
            }
        }
        return nil
    }

    private static func makePixelBufferPool(size: Int) -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size,
            kCVPixelBufferHeightKey as String: size,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
        return pool
    }

    nonisolated func embedding(for face: CGImage) throws -> [Float] {
        guard face.width == Self.inputSize, face.height == Self.inputSize else {
            throw ArcFaceEmbedderError.unexpectedInputSize(got: (face.width, face.height), expected: Self.inputSize)
        }

        var pixelBufferOut: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBufferOut)
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else {
            throw ArcFaceEmbedderError.pixelBufferCreationFailed
        }
        try Self.render(face, into: pixelBuffer)

        let input = try MLDictionaryFeatureProvider(dictionary: [Self.inputName: MLFeatureValue(pixelBuffer: pixelBuffer)])
        let output = try model.prediction(from: input)
        guard let multiArray = output.featureValue(for: Self.outputName)?.multiArrayValue else {
            throw ArcFaceEmbedderError.unexpectedOutput("no '\(Self.outputName)' output")
        }
        guard multiArray.count == embeddingDimension else {
            throw ArcFaceEmbedderError.unexpectedOutput("expected \(embeddingDimension) floats, got \(multiArray.count)")
        }
        return FaceEmbedding.l2Normalized(Self.floatVector(from: multiArray))
    }

    private static func render(_ image: CGImage, into pixelBuffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw ArcFaceEmbedderError.pixelBufferCreationFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    private static func floatVector(from array: MLMultiArray) -> [Float] {
        var result = [Float](repeating: 0, count: array.count)
        for i in 0..<array.count {
            result[i] = array[i].floatValue
        }
        return result
    }
}
