import CoreGraphics

extension BoundingBox {
    /// Scale a 0...1 box into the photo's pixel size.
    func toCGRect(in size: CGSize) -> CGRect {
        CGRect(
            x: x * size.width,
            y: y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}
