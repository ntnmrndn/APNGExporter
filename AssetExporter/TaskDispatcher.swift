//
//  TaskDispatcher.swift
//  AssetExporter
//
//  Created by John Estropia on 2022/02/15.
//

import Foundation


enum TaskDispatcher {

    static func parse(
        arguments: [String],
        singleTask: @escaping (
            _ sourceVideoURL: URL,
            _ maskVideoURL: URL,
            _ outputVideoURL: URL
        ) throws -> Void,
        batchTask: @escaping (
            _ tasks: [
                (
                    sourceVideoURL: URL,
                    maskVideoURL: URL,
                    outputVideoURL: URL
                )
            ],
            _ outputDirectoryURL: URL
        ) throws -> Void,
        unknown: @escaping () throws -> Void
    ) throws {

        switch arguments.count {

        case 8:
            var rootDirectoryURL: URL?
            var sourceSuffix: String?
            var maskSuffix: String?
            var arguments: [String] = .init(arguments.dropFirst())
            while arguments.count > 1 {

                switch arguments.removeFirst() {

                case "-batch":
                    rootDirectoryURL = self.resolveURL(path: arguments.removeFirst())

                case "-source_suffix":
                    sourceSuffix = arguments.removeFirst()

                case "-mask_suffix":
                    maskSuffix = arguments.removeFirst()

                default:
                    try unknown()
                    return
                }
            }
            guard let ouputDirectoryURL = arguments.first.map(self.resolveURL(path:)) else {

                try unknown()
                return
            }
            if let rootDirectoryURL = rootDirectoryURL,
               let sourceSuffix = sourceSuffix,
               let maskSuffix = maskSuffix {

                var urlsByFilename: [
                    String: (
                        sourceVideoURL: URL,
                        maskVideoURL: URL
                    )
                ] = [:]
                for tuple in try self.findSourceAndMaskPairs(
                    from: rootDirectoryURL,
                    sourceSuffix: sourceSuffix,
                    maskSuffix: maskSuffix
                ) {

                    urlsByFilename[tuple.name] = (
                        sourceVideoURL: tuple.sourceVideoURL,
                        maskVideoURL: tuple.maskVideoURL
                    )
                }
                try batchTask(
                    urlsByFilename.map { (filename, pair) in

                        return (
                            sourceVideoURL: pair.sourceVideoURL,
                            maskVideoURL: pair.maskVideoURL,
                            outputVideoURL: ouputDirectoryURL
                                .appendingPathComponent(filename)
                                .appendingPathExtension("mov")
                        )
                    },
                    ouputDirectoryURL
                )
            }
            else {

                try unknown()
            }
        case 4:
            try singleTask(
                self.resolveURL(path: arguments[1]),
                self.resolveURL(path: arguments[2]),
                self.resolveURL(path: arguments[3])
            )
        default:
            try unknown()
        }
    }

    static func performMergeSession(
        taskGroup: DispatchGroup,
        sourceVideoURL: URL,
        maskVideoURL: URL,
        outputVideoURL: URL,
        failure: @escaping (Error?) -> Void
    ) throws {

        taskGroup.enter()

        var mergeSession: MergeSession?
        mergeSession = try .init(
            videoURL: sourceVideoURL,
            maskURL: maskVideoURL,
            outputURL: outputVideoURL,
            success: {

                guard mergeSession != nil else {

                    return
                }
                mergeSession = nil
                taskGroup.leave()
            },
            failure: { error in

                guard mergeSession != nil else {

                    return
                }
                failure(error)
                mergeSession = nil
                taskGroup.leave()
            }
        )

        mergeSession?.start()
    }


    // MARK: Private

    private static let currentDirectoryURL: URL = .init(fileURLWithPath: FileManager.default.currentDirectoryPath)

    private static func resolveURL(path: String) -> URL {

        return .init(fileURLWithPath: path, relativeTo: self.currentDirectoryURL)
    }

    private static func findSourceAndMaskPairs(
        from directoryURL: URL,
        sourceSuffix: String,
        maskSuffix: String
    ) throws -> [
        (
            name: String,
            sourceVideoURL: URL,
            maskVideoURL: URL
        )
    ] {

        var pairs: [
            (
                name: String,
                sourceVideoURL: URL,
                maskVideoURL: URL
            )
        ] = []

        let contents: [URL] = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: []
        )
        for url in contents.sorted(by: { $0.absoluteString < $1.absoluteString }) {

            if url.hasDirectoryPath {

                pairs.append(
                    contentsOf: try self.findSourceAndMaskPairs(
                        from: url,
                        sourceSuffix: sourceSuffix,
                        maskSuffix: maskSuffix
                    )
                )
            }
            else if url.isFileURL {

                let sourceFilename = url.lastPathComponent
                guard sourceFilename.hasSuffix(sourceSuffix) else {

                    continue
                }
                let name: String = .init(sourceFilename.dropLast(sourceSuffix.count))
                let maskVideoURL = url.deletingLastPathComponent()
                    .appendingPathComponent(name + maskSuffix)
                guard contents.contains(maskVideoURL) else {

                    assertionFailure("Missing alpha mask file for file \"\(url)\"")
                    continue
                }
                pairs.append(
                    (
                        name: url.deletingLastPathComponent().lastPathComponent,
                        sourceVideoURL: url,
                        maskVideoURL: maskVideoURL
                    )
                )
            }
        }
        return pairs
    }
}