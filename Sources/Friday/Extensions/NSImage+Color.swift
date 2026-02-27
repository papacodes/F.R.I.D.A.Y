import AppKit
import SwiftUI

extension NSImage {
    /// Extracts a representative accent color from the image.
    /// Samples a 20×20 downscaled version for speed, then boosts brightness if too dark.
    func averageColor(minBrightness: CGFloat = 0.55) -> Color {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .cyan
        }

        let side = 20
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: side, height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .cyan }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        let count = CGFloat(side * side)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            r += CGFloat(pixels[i])     / 255
            g += CGFloat(pixels[i + 1]) / 255
            b += CGFloat(pixels[i + 2]) / 255
        }
        r /= count; g /= count; b /= count

        // Near-black guard
        guard (r + g + b) > 0.09 else { return .cyan }

        var hue: CGFloat = 0, sat: CGFloat = 0, bright: CGFloat = 0, alpha: CGFloat = 0
        NSColor(red: r, green: g, blue: b, alpha: 1)
            .getHue(&hue, saturation: &sat, brightness: &bright, alpha: &alpha)

        if bright < minBrightness {
            bright = minBrightness
            sat = min(sat * 1.4, 1.0)
        }

        return Color(nsColor: NSColor(hue: hue, saturation: sat, brightness: bright, alpha: 1))
    }
}
