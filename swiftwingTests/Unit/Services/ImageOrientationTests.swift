import CoreGraphics
import Foundation
import ImageIO
@testable import swiftwing
import Testing
import UniformTypeIdentifiers

struct ImageOrientationTests {
    @Test func rotatedCaptureIsUploadedUpright() async throws {
        let sideways = try jpeg(width: 80, height: 60, orientation: 6)
        let processed = await ImagePreprocessor().preprocess(sideways).processedData
        let uploaded = try await ImagePreprocessor().resizeAndCompress(processed)

        let pixels = try pixelSize(of: uploaded)
        #expect(pixels.width == 60)
        #expect(pixels.height == 80)
        let orientation = exifOrientation(of: uploaded)
        #expect(orientation == nil || orientation == 1)
    }

    @Test func uprightCaptureKeepsItsPixelSize() async throws {
        let upright = try jpeg(width: 80, height: 60, orientation: 1)
        let processed = await ImagePreprocessor().preprocess(upright).processedData
        let uploaded = try await ImagePreprocessor().resizeAndCompress(processed)

        let pixels = try pixelSize(of: uploaded)
        #expect(pixels.width == 80)
        #expect(pixels.height == 60)
    }

    private func jpeg(width: Int, height: Int, orientation: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Could not create bitmap")
            return Data()
        }
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try #require(props[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(props[kCGImagePropertyPixelHeight] as? Int)
        return (width, height)
    }

    private func exifOrientation(of data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        if let value = props[kCGImagePropertyOrientation] as? Int {
            return value
        }
        if let value = props[kCGImagePropertyOrientation] as? NSNumber {
            return value.intValue
        }
        return nil
    }
}
