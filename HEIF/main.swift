#!/usr/bin/swift
// Copyright (c) by Alexander Borsuk, 2021
// See MIT license in LICENSE file.

import Foundation
import CoreImage
import ArgumentParser
//import AVFoundation

struct HEIF: ParsableCommand {
    enum PathType: EnumerableFlag {
        case xcassets
        case imageset
        case image
    }
    @Option(name: .shortAndLong, help: "compressionQuality")
    var compressionQuality = 0.76
    @Argument
    var path: [String]
    @Flag
    var pathType: PathType = .xcassets
    @Flag(name: .shortAndLong, help: "should delete original images")
    var deleteOriginalImage = false
    var fileManager: FileManager { FileManager.default }

    func run() throws {
        let pathURLs = path.map({ URL(fileURLWithPath: $0) })
        convertPNGToHEIF(imageURLs: {
            switch pathType {
            case .xcassets:
                return pathURLs.flatMap({ parseXcassets($0) })
            case .imageset:
                return pathURLs.flatMap({ parseImageset($0) })
            case .image:
                return pathURLs
            }
        }())
    }

    func files(at path: URL?, pathExtension: String?) -> [URL] {
        guard let path = path else {
            print("invalid path: \(String(describing: path))")
            return []
        }
        do {
            let items = try fileManager.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
            if let pathExtension = pathExtension {
                return items.filter({ $0.pathExtension == pathExtension })
            } else {
                return items
            }
        } catch {
            print("get files at \(path.absoluteString) error: \(error)")
            return []
        }
    }

    func parseImageset(_ imagesetPath: URL) -> [URL] {
        return files(at: imagesetPath, pathExtension: "png")
    }

    func parseXcassets(_ xcassetsURL: URL) -> [URL] {
        guard xcassetsURL.pathExtension == "xcassets" else {
            print("path is not xcassets: \(xcassetsURL)")
            return []
        }
        return files(at: xcassetsURL, pathExtension: nil)
            .filter({ $0.pathExtension == "imageset" })
            .flatMap({ files(at: $0, pathExtension: "png") })
    }

    class ImageContentJson: Codable {
        class Image: Codable {
            var filename: String?
            let idiom: String
            let scale: String
        }
        class Info: Codable {
            let author: String
            let version: Int
        }
        let images: [Image]
        let info: Info
    }

    /// 将Contents.json中的fileName后缀改为heif
    func modifyImageNameInContentJSON(imageUrl: URL) {
        guard let contentFile = files(at: imageUrl.deletingLastPathComponent(), pathExtension: "json").first else { return }

        do {
            let contentData = try Data(contentsOf: contentFile)
            let content = try JSONDecoder().decode(ImageContentJson.self, from: contentData)
            content.images.forEach { image in
                guard let imageName = image.filename else { return }
                image.filename = imageName.replacingOccurrences(of: ".png", with: ".heic")
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(content).write(to: contentFile, options: [.atomic])
        } catch {
            print("failtd modifyImageNameInContentJSON with \(imageUrl). error: \(error)")
        }
    }

    func convertPNGToHEIF(imageURLs: [URL]) {
        for imageUrl in imageURLs {
            let nsOptions = NSDictionary(dictionary: [
                kCGImageDestinationLossyCompressionQuality: compressionQuality
            ])
            guard
                let image = CIImage(contentsOf: imageUrl),
                let colorSpace = image.colorSpace,
                let options = nsOptions as? [CIImageRepresentationOption: Any]
            else {
                print("failed get image with \(imageUrl)")
                return
            }
            let context = CIContext(options: nil)
            let heicUrl = imageUrl.deletingPathExtension().appendingPathExtension("heic")

            do {
                try context.writeHEIFRepresentation(
                    of:image,
                    to:heicUrl,
                    format: CIFormat.ARGB8,
                    colorSpace: colorSpace,
                    options: options
                )
                if deleteOriginalImage {
                    try fileManager.removeItem(at: imageUrl)
                }
                
                modifyImageNameInContentJSON(imageUrl: imageUrl)
                
            } catch {
                print("writeHEIFRepresentation error: \(error)")
            }
        }
    }
//    func convertImage(type: AVFileType, imageURLs: [URL]) {
//        for imageURL in imageURLs {
//            guard
//                let data = CIImage(contentsOf: imageURL)?.data(type: type, compressionQuality: compressionQuality)
//            else {
//                return
//            }
//            let heicUrl = imageURL.deletingPathExtension().appendingPathExtension("heif")
//            do {
//                try data.write(to: heicUrl)
//            } catch {
//                print("write image error: \(error)")
//            }
//        }
//    }

}


//enum HEICError: Error {
//    case heicNotSupported
//    case cgImageMissing
//    case couldNotFinalize
//}
//extension CIImage {
//    func data(type: AVFileType, compressionQuality: Double) -> Data {
//        let data = NSMutableData()
//        do {
//            // 1
//            guard let imageDestination = CGImageDestinationCreateWithData(
//                data, type as CFString, 1, nil
//            )
//            else {
//                throw HEICError.heicNotSupported
//            }
//
//            // 2
//            guard let cgImage = self._cgImage else {
//                throw HEICError.cgImageMissing
//            }
//
//            // 3
//            let options: NSDictionary = [
//                kCGImageDestinationLossyCompressionQuality: compressionQuality
//            ]
//
//            // 4
//            CGImageDestinationAddImage(imageDestination, cgImage, options)
//            guard CGImageDestinationFinalize(imageDestination) else {
//                throw HEICError.couldNotFinalize
//            }
//        } catch {
//            print("get heif data error: \(error)")
//        }
//
//        return data as Data
//    }
//    var _cgImage: CGImage? {
//        let context = CIContext(options: nil)
//        guard let cgImage = context.createCGImage(self, from: self.extent) else {
//            print("fail get CGImage from CIImage.")
//            return nil
//        }
//        return cgImage
//    }
//}


HEIF.main()
