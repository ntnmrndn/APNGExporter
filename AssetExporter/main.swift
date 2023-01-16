//
//  main.swift
//  AssetExporter
//
//  Created by John Estropia on 2022/02/15.
//

import Foundation
import AVFoundation


let taskGroup: DispatchGroup = .init()


try TaskDispatcher.performMergeSession(
  taskGroup: taskGroup,
  sourceVideoURL: .init(fileURLWithPath: "/Users/antoine.marandon/Desktop/08_render-Mitene.apng"),
  maskVideoURL: nil,
  outputVideoURL: .init(fileURLWithPath: "/Users/antoine.marandon/Desktop/08_render-Mitene3.mov"),
  failure: { error 

//    failed -= 1
    print("Failed with error: \(error?.localizedDescription ?? "nil")")
  }
)


//
//try TaskDispatcher.parse(
//    arguments: CommandLine.arguments,
//    singleTask: { sourceVideoURL, maskVideoURL, outputVideoURL in
//
//        print("Merging…")
//
//        try TaskDispatcher.performMergeSession(
//            taskGroup: taskGroup,
//            sourceVideoURL: sourceVideoURL,
//            maskVideoURL: maskVideoURL,
//            outputVideoURL: outputVideoURL,
//            failure: { error in
//
//                print("Failed with error: \(error?.localizedDescription ?? "nil")")
//            }
//        )
//        taskGroup.notify(queue: .main) {
//
//            print("Merged file: \"\(outputVideoURL)\"")
//        }
//    },
//    batchTask: { tasks, ouputDirectoryURL in
//
//        print("Merging \(tasks.count) file(s)…")
//
//        var failed = 0
//        for task in tasks {
//
//            try TaskDispatcher.performMergeSession(
//                taskGroup: taskGroup,
//                sourceVideoURL: task.sourceVideoURL,
//                maskVideoURL: task.maskVideoURL,
//                outputVideoURL: task.outputVideoURL,
//                failure: { error in
//
//                    failed -= 1
//                    print("Failed with error: \(error?.localizedDescription ?? "nil")")
//                }
//            )
//        }
//        taskGroup.notify(queue: .main) {
//
//            print("Merged \(tasks.count - failed) file(s) to folder: \"\(ouputDirectoryURL)\"")
//        }
//    },
//    unknown: {
//
//        print("Unknown parameters. Valid commands:")
//        print("<input URL> [<mask URL>] <output file URL>")
//        print("-batch <root directory URL> -source_suffix _sozai.mp4 -mask_suffix _alpha.mp4 <output directory URL>")
//        exit(1)
//    }
//)
//
//
taskGroup.wait()
