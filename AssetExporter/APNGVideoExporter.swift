//
//  APNGVideoExporter.swift
//  AssetExporter
//
//  Created by Antoine Marandon on 29/07/2022.
//

import AVFoundation
import Foundation
import AppKit
@testable import APNGKit

final class APNGVideoExporter {

  let renderer:  APNGImageRenderer
  init(
    apng: APNGImage,
    outputURL: URL,
    success: @escaping () -> Void,
    failure: @escaping (Error?) -> Void
  ) throws {

    self.outputURL = outputURL
    self.success = success
    self.failure = failure
    self.apng = apng
    _ = try? FileManager.default.removeItem(at: self.outputURL)
    _ = try? FileManager.default.createDirectory(
      at: self.outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: nil
    )
    let writer: AVAssetWriter = try .init(outputURL: outputURL, fileType: .mov)
    writer.shouldOptimizeForNetworkUse = true

    self.renderer = try APNGImageRenderer(decoder: apng.decoder)
    try renderer.renderNextSync()

    self.writer = writer
    let sampleImage = self.apng.loadedFrames.first!


    let videoInput: AVAssetWriterInput = .init(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
        AVVideoWidthKey: sampleImage.frameControl.width,
        AVVideoHeightKey: sampleImage.frameControl.height,
        AVVideoCompressionPropertiesKey: [
          AVVideoQualityKey: 0.1 // 0.05 => Bad
        //  AVVideoAverageBitRateKey: 800,

        ]
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
        .init(kCVPixelBufferWidthKey): sampleImage.frameControl.width,
        .init(kCVPixelBufferHeightKey): sampleImage.frameControl.height,
        .init(kCVPixelBufferOpenGLCompatibilityKey): true
      ]
    )

    self.inputQueue = .init(
      label: "MergeSession.inputQueue",
      qos: .userInitiated,
      autoreleaseFrequency: .workItem
    )

    self.writer.startWriting()
    self.writer.startSession(atSourceTime: .zero)
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
      self.complete()
    }
  }


  // MARK: Private

  private let apng: APNGImage
  private let outputURL: URL
  private let writer: AVAssetWriter
  private let videoInput: AVAssetWriterInput
  private let videoPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor

  private let inputQueue: DispatchQueue

  private var currentFrame: Int = 0
  private var currentTime: CMTime = .zero

  private let success: () -> Void
  private let failure: (Error?) -> Void

  private func finish() {

    self.videoInput.markAsFinished()
    switch (self.writer.status) {

    case .cancelled:
      return

    case .failed:
      self.complete()

    case _:
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

  let ciContext =  CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)

  func createPixelBufferFrom(image: CIImage) -> CVPixelBuffer? {
    // based on https://stackoverflow.com/questions/54354138/how-can-you-make-a-cvpixelbuffer-directly-from-a-ciimage-instead-of-a-uiimage-in

    let attrs = [
      kCVPixelBufferCGImageCompatibilityKey: false,
      kCVPixelBufferCGBitmapContextCompatibilityKey: false,
      kCVPixelBufferWidthKey: Int(image.extent.width),
      kCVPixelBufferHeightKey: Int(image.extent.height)
    ] as CFDictionary
    var pixelBuffer : CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(image.extent.width), Int(image.extent.height), kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)

    if status == kCVReturnInvalidPixelFormat {
      print("status == kCVReturnInvalidPixelFormat")
    }
    if status == kCVReturnInvalidSize {
      print("status == kCVReturnInvalidSize")
    }
    if status == kCVReturnPixelBufferNotMetalCompatible {
      print("status == kCVReturnPixelBufferNotMetalCompatible")
    }
    if status == kCVReturnPixelBufferNotOpenGLCompatible {
      print("status == kCVReturnPixelBufferNotOpenGLCompatible")
    }

    guard (status == kCVReturnSuccess) else {
      return nil
    }

    ciContext.render(image, to: pixelBuffer!)
    return pixelBuffer
  }


  private func encodeReadySamples() {

    let input = self.videoInput
    let videoPixelBufferAdaptor = self.videoPixelBufferAdaptor

    while input.isReadyForMoreMediaData {

      autoreleasepool {
        guard currentFrame < apng.numberOfFrames else {
          self.finish()
          return
        }
        try! renderer.renderNextSync()
        let frame = apng.loadedFrames[currentFrame]
        let image = apng.cachedFrameImage(at: currentFrame)!
        
        let pixelBuffer = createPixelBufferFrom(image: CIImage(cgImage: image))!

        guard
          videoPixelBufferAdaptor.append(
            pixelBuffer,
          withPresentationTime: currentTime
          )
        else {
          self.finish()
          return
        }
        self.currentTime = CMTimeAdd(self.currentTime, .init(seconds: frame.frameControl.duration, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
        self.currentFrame += 1
      }
    }
  }
}
