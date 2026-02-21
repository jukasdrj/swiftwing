import CoreGraphics

extension BoundingBox {
    /// Convert normalized (0.0-1.0) bounding box to a CGRect within a given pixel size
    func toCGRect(in size: CGSize) -> CGRect {
        CGRect(
            x: x * size.width,
            y: y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}
