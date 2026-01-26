#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// SwiftWing App Icon Generator
// Creates "Swiss Glass Book Spine" design for iOS 26 Liquid Glass

let size: CGFloat = 1024
let context = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

// Swiss Colors
let black = CGColor(red: 0x0D/255.0, green: 0x0D/255.0, blue: 0x0D/255.0, alpha: 1.0)
let white = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
let internationalOrange = CGColor(red: 0xFF/255.0, green: 0x4F/255.0, blue: 0x00/255.0, alpha: 1.0)

// Fill black background
context.setFillColor(black)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Book spine dimensions (centered)
let spineWidth: CGFloat = 200
let spineHeight: CGFloat = 720
let spineX = (size - spineWidth) / 2
let spineY = (size - spineHeight) / 2

// Orange stripe (left edge of spine, 40px wide)
let stripeWidth: CGFloat = 40
context.setFillColor(internationalOrange)
context.fill(CGRect(x: spineX, y: spineY, width: stripeWidth, height: spineHeight))

// White book spine (offset by stripe width)
context.setFillColor(white)
context.fill(CGRect(x: spineX + stripeWidth, y: spineY, width: spineWidth - stripeWidth, height: spineHeight))

// Create image
guard let cgImage = context.makeImage() else {
    print("Error: Failed to create CGImage")
    exit(1)
}

// Save to PNG
let outputURL = URL(fileURLWithPath: "swiftwing/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    print("Error: Failed to create image destination")
    exit(1)
}

CGImageDestinationAddImage(destination, cgImage, nil)

if CGImageDestinationFinalize(destination) {
    print("✅ App icon generated: \(outputURL.path)")
    print("   Size: 1024x1024px")
    print("   Design: Swiss Glass Book Spine")
    print("   Colors: Black (#0D0D0D) + White + International Orange (#FF4F00)")
} else {
    print("Error: Failed to write PNG file")
    exit(1)
}
