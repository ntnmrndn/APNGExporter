//
//  main.swift
//  AssetExporter
//
//  Created by John Estropia on 2022/02/15.
//

import Foundation
import AVFoundation
import Darwin.C.stdlib
import APNGKit

guard CommandLine.arguments.count >= 3 else {
  print("Usage: src dst [0.0-1.0 quality, default 0.2]")
  exit(EXIT_FAILURE)
}
let source = URL(filePath: CommandLine.arguments[1])
let destination = URL(filePath: CommandLine.arguments[2])
let quality: Float
if CommandLine.arguments.count >= 4 {
  if let value = NumberFormatter().number(from: CommandLine.arguments[3])?.floatValue, value > 0, value <= 1.0 {
    quality = value
  } else {
    print("unable to parese quality '\(CommandLine.arguments[3])'")
    exit(EXIT_FAILURE)
  }
} else {
  quality = 0.2
}


let taskGroup: DispatchGroup = .init()

let apng = try APNGImage(data: try! Data.init(contentsOf: source), decodingOptions: [.fullFirstPass, .cacheDecodedImages, .loadFrameData])
taskGroup.enter()

do {
 let exporter = try APNGVideoExporter(
      apng: apng,
      outputURL: destination,
      quality: quality,
      success: {
        taskGroup.leave()
      },
      failure: { error in
        print("Error")
        print(error ?? "")
        exit(EXIT_FAILURE)
      }
    )
  exporter.start()
}

taskGroup.wait()

