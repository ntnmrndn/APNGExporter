//
//  AlphaMaskCompositor.swift
//  AssetExporter
//
//  Created by John Estropia on 2022/02/10.
//

import AppKit
import AVFoundation
import Dispatch
import Foundation
import ObjectiveC
import CoreImage


final class AlphaMaskCompositor: NSObject, AVVideoCompositing {

    override init() {
        super.init()
    }


    // MARK: AVVideoCompositing

    @objc
    dynamic let sourcePixelBufferAttributes: [String: Any]? = [
        .init(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
        .init(kCVPixelBufferOpenGLCompatibilityKey): true
    ]

    @objc
    dynamic let requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        .init(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
        .init(kCVPixelBufferOpenGLCompatibilityKey): true
    ]

    @objc
    dynamic func renderContextChanged(
        _ newRenderContext: AVVideoCompositionRenderContext
    ) {}

    @objc
    dynamic func startRequest(
        _ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest
    ) {

        self.renderOperation.addOperation {

            autoreleasepool {

                guard
                    let instruction = asyncVideoCompositionRequest.videoCompositionInstruction as? Instruction
                else {

                    asyncVideoCompositionRequest.finish(
                        with: NSError(
                            domain: "com.johnestropia.mergersession",
                            code: 760,
                            userInfo: [
                                NSLocalizedFailureErrorKey: "Missing \(String(describing: AlphaMaskCompositor.Instruction.self)) for compositor."
                            ]
                        )
                    )
                    return
                }
                guard
                    let sourcePixels = asyncVideoCompositionRequest.sourceFrame(
                        byTrackID: instruction.sourceTrackID
                    ),
                    let maskPixels = asyncVideoCompositionRequest.sourceFrame(
                        byTrackID: instruction.maskTrackID
                    )
                else {

                    asyncVideoCompositionRequest.finish(
                        with: NSError(
                            domain: "com.johnestropia.mergersession",
                            code: 760,
                            userInfo: [
                                NSLocalizedFailureErrorKey: "Source and mask tracks not found"
                            ]
                        )
                    )
                    return
                }

                let sourceImage: CIImage = .init(cvPixelBuffer: sourcePixels)
                let maskImage: CIImage = .init(cvPixelBuffer: maskPixels)
                let backgroundImage: CIImage = .init(color: .clear)
                    .cropped(to: sourceImage.extent)

                guard
                    let blendMaskFilter: CIFilter = .init(
                        name: "CIBlendWithMask",
                        parameters: [
                            kCIInputImageKey: sourceImage,
                            kCIInputMaskImageKey: maskImage,
                            kCIInputBackgroundImageKey: backgroundImage
                        ]
                    ),
                    let outputImage = blendMaskFilter.outputImage
                else {

                    asyncVideoCompositionRequest.finish(
                        with: NSError(
                            domain: "com.johnestropia.mergersession",
                            code: 760,
                            userInfo: [
                                NSLocalizedFailureErrorKey: "`CIBlendWithMask` filter not supported."
                            ]
                        )
                    )
                    return
                }

                var newBuffer: CVPixelBuffer?
                guard
                    case kCVReturnSuccess = CVPixelBufferCreate(
                        kCFAllocatorDefault,
                        CVPixelBufferGetWidth(sourcePixels),
                        CVPixelBufferGetHeight(sourcePixels),
                        CVPixelBufferGetPixelFormatType(sourcePixels),
                        nil,
                        &newBuffer
                    ),
                    let newBuffer = newBuffer
                else {

                    asyncVideoCompositionRequest.finish(
                        withComposedVideoFrame: sourcePixels
                    )
                    return
                }

                instruction.context.render(outputImage, to: newBuffer)
                asyncVideoCompositionRequest.finish(
                    withComposedVideoFrame: newBuffer
                )
            }
        }
    }

    @objc
    dynamic func cancelAllPendingVideoCompositionRequests() {

        self.renderOperation.cancelAllOperations()
        self.renderOperation = Self.newRenderOperation()
    }


    // MARK: Private

    private let renderQueue: DispatchQueue = .init(
        label: "AlphaMaskCompositor.renderQueue",
        qos: .userInitiated,
        autoreleaseFrequency: .workItem
    )

    private var renderOperation: OperationQueue = AlphaMaskCompositor.newRenderOperation()

    private static func newRenderOperation() -> OperationQueue {

        let operation: OperationQueue = .init()
        operation.maxConcurrentOperationCount = 1
        operation.qualityOfService = .userInitiated
        return operation
    }


    // MARK: - Instruction

    final class Instruction: AVMutableVideoCompositionInstruction {

        init(
            sourceTrackID: CMPersistentTrackID,
            maskTrackID: CMPersistentTrackID,
            timeRange: CMTimeRange
        ) {

            self.sourceTrackID = sourceTrackID
            self.maskTrackID = maskTrackID
            super.init()

            self.timeRange = timeRange
            self.enablePostProcessing = true
            self.backgroundColor = NSColor.clear.cgColor
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {

            fatalError()
        }


        // MARK: AVVideoCompositionInstructionProtocol

        override var containsTweening: Bool {

            return false
        }

        override var requiredSourceTrackIDs: [NSValue] {

            return [self.sourceTrackID, self.maskTrackID]
                .map({ NSNumber(value: $0) })
        }

        override var passthroughTrackID: CMPersistentTrackID {

            return kCMPersistentTrackID_Invalid // self.sourceTrackID
        }


        // MARK: FilePrivate

        fileprivate let sourceTrackID: CMPersistentTrackID
        fileprivate let maskTrackID: CMPersistentTrackID
        fileprivate let context: CIContext = .init()
    }
}
