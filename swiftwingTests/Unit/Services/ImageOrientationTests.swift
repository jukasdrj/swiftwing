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
        #expect(orientation == 1)
    }

    @Test func uprightCaptureKeepsItsPixelSize() async throws {
        let upright = try jpeg(width: 80, height: 60, orientation: 1)
        let processed = await ImagePreprocessor().preprocess(upright).processedData
        let uploaded = try await ImagePreprocessor().resizeAndCompress(processed)

        let pixels = try pixelSize(of: uploaded)
        #expect(pixels.width == 80)
        #expect(pixels.height == 60)
    }

    @Test func uprightJPEGInsideTheCapIsNotEncodedAgain() async throws {
        let original = try jpeg(width: 80, height: 60, orientation: 1, red: 0.5, green: 0.5, blue: 0.5)
        let prepared = await ImagePreprocessor().preprocess(original)

        #expect(prepared.didReencode == false)
        #expect(prepared.wasRotated == false)
        #expect(prepared.brightnessAdjustment == 0)
        #expect(prepared.processedData == original)

        let uploaded = try await ImagePreprocessor().resizeAndCompress(prepared.processedData)
        #expect(uploaded == original)
    }

    @Test func wideJPEGIsScaledOnceToTheUploadEdge() async throws {
        let original = try jpeg(width: 2400, height: 1200, orientation: 1, red: 0.5, green: 0.5, blue: 0.5)
        let prepared = await ImagePreprocessor().preprocess(original)
        let uploaded = try await ImagePreprocessor().resizeAndCompress(prepared.processedData)

        #expect(prepared.didReencode)
        #expect(uploaded == prepared.processedData)
        let pixels = try pixelSize(of: uploaded)
        #expect(pixels.width == 1920)
        #expect(pixels.height == 960)
    }

    @Test func narrowCropStillTurnsOnce() async throws {
        let original = try jpeg(width: 40, height: 100, orientation: 1, red: 0.5, green: 0.5, blue: 0.5)
        let prepared = await ImagePreprocessor().preprocess(original)

        #expect(prepared.wasRotated)
        #expect(prepared.didReencode)
        let uploaded = try await ImagePreprocessor().resizeAndCompress(prepared.processedData)
        #expect(uploaded == prepared.processedData)
        let pixels = try pixelSize(of: uploaded)
        #expect(pixels.width == 100)
        #expect(pixels.height == 40)
    }

    @Test func onDeviceDecodeBakesSidewaysExif() async throws {
        let sideways = try jpeg(width: 80, height: 60, orientation: 6)
        let decoded = try await OnDeviceScanner().decodeScanImage(from: sideways)

        #expect(decoded.exifOrientation == 6)
        #expect(decoded.image.width == 60)
        #expect(decoded.image.height == 80)
    }

    private func jpeg(
        width: Int,
        height: Int,
        orientation: Int,
        red: CGFloat = 0.8,
        green: CGFloat = 0.2,
        blue: CGFloat = 0.1
    ) throws -> Data {
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
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
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
