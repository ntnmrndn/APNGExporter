//
//  MergeSession.swift
//  AssetExporter
//
//  Created by John Estropia on 2022/02/10.
//

import AVFoundation
import Foundation
import AppKit


final class AlphaMaskVideoMergeSession {

    init(
        videoURL: URL,
        maskURL: URL,
        outputURL: URL,
        success: @escaping () -> Void,
        failure: @escaping (Error?) -> Void
    ) throws {

        self.outputURL = outputURL
        self.success = success
        self.failure = failure

        _ = try? FileManager.default.removeItem(at: self.outputURL)
        _ = try? FileManager.default.createDirectory(
            at: self.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        self.videoAsset = .init(
            url: videoURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        self.maskAsset = .init(
            url: maskURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )

        let sourceVideoTrack: AVAssetTrack = self.videoAsset.tracks(withMediaType: .video)[0]
        let maskVideoTrack: AVAssetTrack = self.maskAsset.tracks(withMediaType: .video)[0]

        let asset: AVMutableComposition = .init()
        let sourceVideoMutableTrack = asset.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )!
        try sourceVideoMutableTrack.insertTimeRange(
            sourceVideoTrack.timeRange,
            of: sourceVideoTrack,
            at: sourceVideoTrack.timeRange.start
        )
        let maskVideoMutableTrack = asset.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )!
        try maskVideoMutableTrack.insertTimeRange(
            maskVideoTrack.timeRange,
            of: maskVideoTrack,
            at: maskVideoTrack.timeRange.start
        )

        self.temporaryAsset = asset
        self.reader = try .init(asset: asset)

        let writer: AVAssetWriter = try .init(outputURL: outputURL, fileType: .mov)
        writer.shouldOptimizeForNetworkUse = true
//            writer.metadata = [:] // EXIF
        self.writer = writer

        let timeRange = sourceVideoTrack.timeRange
        self.reader.timeRange = timeRange

        let videoTracks = asset.tracks(withMediaType: .video)

        let videoOutput: AVAssetReaderVideoCompositionOutput = .init(
            videoTracks: videoTracks,
            videoSettings: [
                .init(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
                .init(kCVPixelBufferOpenGLCompatibilityKey): true
            ]
        )
        self.videoOutput = videoOutput

        let videoComposition: AVMutableVideoComposition = .init(propertiesOf: asset)
        videoComposition.customVideoCompositorClass = AlphaMaskCompositor.self
        videoComposition.instructions = [
            AlphaMaskCompositor.Instruction(
                sourceTrackID: sourceVideoMutableTrack.trackID,
                maskTrackID: maskVideoMutableTrack.trackID,
                timeRange: timeRange
            )
        ]
//        videoComposition.animationTool = demoAnimationTool(videoSize: videoComposition.renderSize)

        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false
        self.videoComposition = videoComposition

        if self.reader.canAdd(videoOutput) {

            self.reader.add(videoOutput)
        }

        let videoSize = videoComposition.renderSize
        let videoInput: AVAssetWriterInput = .init(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
                AVVideoWidthKey: NSNumber(floatLiteral: videoSize.width),
                AVVideoHeightKey: NSNumber(floatLiteral: videoSize.height),
                AVVideoCompressionPropertiesKey: [
///                  AVVideoQualityKey: NSNumber(floatLiteral: 1)
                AVVideoAverageBitRateKey: 800,

                ]
//                    AVVideoCompressionPropertiesKey: [
//                        AVVideoAverageBitRateKey: (bitsPerPize * videoSize.width * videoSize.height),
//                        AVVideoProfileLevelKey: AVVideoProfileLevelH264Baseline41
//                    ]
            ]
        )
        videoInput.expectsMediaDataInRealTime = false
        self.videoInput = videoInput

        if self.writer.canAdd(videoInput) {

            self.writer.add(videoInput)
        }
        self.videoPixelBufferAdaptor = .init(
            assetWriterInput: self.videoInput,
            sourcePixelBufferAttributes: [
                .init(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
                .init(kCVPixelBufferWidthKey): videoSize.width,
                .init(kCVPixelBufferHeightKey): videoSize.height,
                .init(kCVPixelBufferOpenGLCompatibilityKey): true
            ]
        )

        self.inputQueue = .init(
            label: "MergeSession.inputQueue",
            qos: .userInitiated,
            autoreleaseFrequency: .workItem
        )

        self.writer.startWriting()
        self.reader.startReading()
        self.writer.startSession(atSourceTime: timeRange.start)
    }

    func start() {

        self.videoInput.requestMediaDataWhenReady(on: self.inputQueue) { [weak self] in

            guard let self = self else {

                return
            }
            self.encodeReadySamples()
        }
    }

    func cancel() {

        self.inputQueue.async {

            self.writer.cancelWriting()
            self.reader.cancelReading()
            self.complete()
        }
    }


    // MARK: Private

    private let videoAsset: AVURLAsset
    private let maskAsset: AVURLAsset

    private let temporaryAsset: AVMutableComposition
    private let videoComposition: AVMutableVideoComposition

    private let reader: AVAssetReader
    private let videoOutput: AVAssetReaderVideoCompositionOutput

    private let outputURL: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let videoPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor

    private let inputQueue: DispatchQueue

    private var progress: Double = 0

    private let success: () -> Void
    private let failure: (Error?) -> Void

    private func finish() {

        switch (self.reader.status, self.writer.status) {

        case (.cancelled, _),
             (_, .cancelled):
            return

        case (_, .failed):
            self.complete()

        case (.failed, _):
            self.writer.cancelWriting()
            self.complete()

        case (_, _):
            self.writer.finishWriting(
                completionHandler: self.complete
            )
        }
    }

    private func complete() {

        switch self.writer.status {

        case .failed,
             .cancelled:
            _ = try? FileManager.default.removeItem(at: self.outputURL)
            self.failure(self.writer.error)

        case .completed:
            let deletePrefix = "\(self.outputURL.lastPathComponent).sb-"
            for fileURL in (
                try? FileManager.default.contentsOfDirectory(
                    at: self.outputURL.deletingLastPathComponent(),
                    includingPropertiesForKeys: nil,
                    options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants]
                )
            ) ?? [] {

                guard fileURL.lastPathComponent.hasPrefix(deletePrefix) else {

                    continue
                }
                _ = try? FileManager.default.removeItem(at: fileURL)
            }
            self.success()

        case .unknown,
             .writing:
            self.failure(self.writer.error)

        @unknown default:
            self.failure(self.writer.error)
        }
    }

    private func encodeReadySamples() {

        let output = self.videoOutput
        let input = self.videoInput
        let reader = self.reader
        let videoPixelBufferAdaptor = self.videoPixelBufferAdaptor

        while input.isReadyForMoreMediaData {

            autoreleasepool {

                let sampleBuffer: CMSampleBuffer?
                if case .reading = reader.status {

                    sampleBuffer = output.copyNextSampleBuffer()
                }
                else {

                    sampleBuffer = nil
                }
                if let sampleBuffer = sampleBuffer {

                    if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {

                        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
                        defer {

                            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                        }
                        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                        guard
                            videoPixelBufferAdaptor.append(
                                pixelBuffer,
                                withPresentationTime: currentTime
                            )
                        else {

                            reader.cancelReading()
                            self.finish()
                            return
                        }
//                        let progress = CMTimeGetSeconds(currentTime) / CMTimeGetSeconds(reader.timeRange.duration)
//                        print("Progress: \(progress)")
                    }
                }
                else {

                    input.markAsFinished()
                    self.finish()
                }
            }
        }
    }
}


func demoAnimationTool(videoSize: CGSize) -> AVVideoCompositionCoreAnimationTool {

    let bounds: CGRect = .init(origin: .zero, size: videoSize)
    let parentLayer: CALayer = {

        let layer: CALayer = .init()
        layer.frame = bounds
        layer.anchorPoint = .zero
        layer.position = .zero
        layer.isGeometryFlipped = false
        return layer
    }()
    let videoLayer: CALayer = {

        let layer: CALayer = .init()
        layer.frame = bounds
        layer.anchorPoint = .zero
        layer.position = .zero
        layer.isGeometryFlipped = false
        return layer
    }()

    parentLayer.addSublayer(videoLayer)


    let stampLayer: CALayer = {

        let image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 80, weight: .bold)
            )!
            .image(with: .yellow)

        let layer: CALayer = .init()
        layer.bounds = .init(origin: .zero, size: image.size)
        layer.anchorPoint = .init(x: 0.5, y: 0.5)
        layer.position = .init(x: bounds.midX, y: bounds.midY)
        layer.isGeometryFlipped = false
        layer.contents = image

        layer.add(
            {
                let animation: CABasicAnimation = .init(keyPath: "transform.rotation")
                animation.fromValue = 0
                animation.toValue = (CGFloat.pi * 2)
                animation.repeatCount = .infinity
                animation.duration = 5
                animation.fillMode = .both
                animation.beginTime = AVCoreAnimationBeginTimeAtZero
                animation.isRemovedOnCompletion = false

                return animation
            }(),
            forKey: "spin"
        )

        return layer
    }()

    parentLayer.addSublayer(stampLayer)

    return .init(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
}


extension NSImage {
    func image(with tintColor: NSColor) -> NSImage {
        if self.isTemplate == false {
            return self
        }

        let image = self.copy() as! NSImage
        image.lockFocus()

        tintColor.set()

        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceIn)

        image.unlockFocus()
        image.isTemplate = false

        return image
    }
}
