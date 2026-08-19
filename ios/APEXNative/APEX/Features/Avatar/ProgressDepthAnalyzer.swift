import AVFoundation
import CoreImage
import UIKit
import Vision

/*
 * Live distance and subject reading for the progress camera.
 *
 * Distance is the variable that quietly ruins a comparison. Two photos taken
 * a step apart change apparent size far more than a month of training does,
 * and nothing on screen normally tells you. The depth camera does: LiDAR on
 * the rear of a Pro device, TrueDepth on the front, both surfaced through the
 * same API.
 *
 * Orientation is inferred rather than guessed at. Vision can find a human
 * body in the frame and, separately, a face. A body with a face is someone
 * looking at the camera; a body without one is someone facing away, which is
 * exactly the back pose this feature asks for. That inference is honest about
 * itself: when neither is found it says so instead of inventing a reading.
 */
@MainActor
@Observable
final class ProgressDepthAnalyzer {
    enum Subject: String, Sendable {
        case none
        case facingCamera
        case profile
        case facingAway

        var label: String {
            switch self {
            case .none: "No subject"
            case .facingCamera: "Facing camera"
            case .profile: "Profile"
            case .facingAway: "Facing away"
            }
        }

        var systemImage: String {
            switch self {
            case .none: "person.slash"
            case .facingCamera: "person.crop.circle"
            case .profile: "person.crop.circle.badge.questionmark"
            case .facingAway: "person.crop.circle.dashed"
            }
        }
    }

    /// Metres from the lens to the subject, when a depth camera is present.
    private(set) var distanceMetres: Double?
    private(set) var subject: Subject = .none
    private(set) var hasDepth = false
    /// True when the subject sits inside the range a full-body frame needs.
    var isWellPlaced: Bool {
        guard let distanceMetres else { return false }
        return (1.6...3.2).contains(distanceMetres)
    }

    var distanceText: String? {
        guard let distanceMetres else { return nil }
        return String(format: "%.2f m", distanceMetres)
    }

    /// Advice only when it is actionable, and never when there is no reading.
    var placementHint: String? {
        guard let distanceMetres else { return nil }
        if distanceMetres < 1.6 { return "Step back" }
        if distanceMetres > 3.2 { return "Step closer" }
        return nil
    }

    func update(distance: Double?, subject: Subject, hasDepth: Bool) {
        self.distanceMetres = distance
        self.subject = subject
        self.hasDepth = hasDepth
    }
}

/*
 * Runs the two Vision requests and samples the depth map. Lives off the main
 * actor because it is fed from the capture queue at frame rate.
 */
final class ProgressFrameAnalyzer: NSObject, @unchecked Sendable {
    private let sequence = VNSequenceRequestHandler()
    private var lastRun = Date.distantPast
    /// Six readings a second is enough for a person to react to, and leaves
    /// the camera preview smooth.
    private let interval: TimeInterval = 1.0 / 6

    var onReading: (@Sendable (Double?, ProgressDepthAnalyzer.Subject, Bool) -> Void)?

    func analyze(pixelBuffer: CVPixelBuffer, depth: AVDepthData?) {
        let now = Date()
        guard now.timeIntervalSince(lastRun) >= interval else { return }
        lastRun = now

        var subject = ProgressDepthAnalyzer.Subject.none
        var region: CGRect?

        let humans = VNDetectHumanRectanglesRequest()
        humans.upperBodyOnly = false
        let faces = VNDetectFaceRectanglesRequest()

        try? sequence.perform([humans, faces], on: pixelBuffer, orientation: .leftMirrored)

        let human = (humans.results ?? []).max { $0.confidence < $1.confidence }
        let face = (faces.results ?? []).max { $0.confidence < $1.confidence }

        if let human {
            region = human.boundingBox
            if let face, face.confidence > 0.4 {
                /* A face much narrower than the shoulders reads as a profile
                   rather than someone square to the camera. */
                subject = face.boundingBox.width < human.boundingBox.width * 0.32 ? .profile : .facingCamera
            } else {
                subject = .facingAway
            }
        } else if let face, face.confidence > 0.4 {
            region = face.boundingBox
            subject = .facingCamera
        }

        let distance = depth.flatMap { sample($0, in: region) }
        onReading?(distance, subject, depth != nil)
    }

    /// Median depth over the subject, which ignores the stray far readings a
    /// doorway or a mirror puts inside the same rectangle.
    private func sample(_ depth: AVDepthData, in region: CGRect?) -> Double? {
        let converted = depth.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depth
            : depth.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = converted.depthDataMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }

        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard width > 0, height > 0,
              let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(map)

        /* Vision reports a normalised, bottom-left origin rectangle; the depth
           map is top-left. Default to the middle third when nothing was found. */
        let box = region ?? CGRect(x: 0.33, y: 0.33, width: 0.34, height: 0.34)
        let minX = Int(max(0, box.minX) * Double(width))
        let maxX = Int(min(1, box.maxX) * Double(width))
        let minY = Int((1 - min(1, box.maxY)) * Double(height))
        let maxY = Int((1 - max(0, box.minY)) * Double(height))
        guard maxX > minX, maxY > minY else { return nil }

        var samples: [Float] = []
        samples.reserveCapacity(256)
        let strideX = max(1, (maxX - minX) / 16)
        let strideY = max(1, (maxY - minY) / 16)
        for y in Swift.stride(from: minY, to: maxY, by: strideY) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in Swift.stride(from: minX, to: maxX, by: strideX) {
                let value = row[x]
                if value.isFinite, value > 0.15, value < 8 { samples.append(value) }
            }
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        return Double(samples[samples.count / 2])
    }
}
