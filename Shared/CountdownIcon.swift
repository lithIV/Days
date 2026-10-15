import SwiftUI
import UIKit

/// Custom countdown icons, stored as PNGs (alpha kept) in the shared App
/// Group container so the widget can draw them too.
enum IconStore {
    static let directory: URL = {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.resolvedAppGroup)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let loaded = UIImage(contentsOfFile: directory.appendingPathComponent(name).path) else { return nil }
        let image = trimmingTransparentEdges(loaded)
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// Crops fully see-through borders so the visible artwork lines up with
    /// text instead of floating inside invisible padding.
    static func trimmingTransparentEdges(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return image }

        // Bitmap rows run top to bottom, matching CGImage cropping coordinates.
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w where pixels[row + x * 4 + 3] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY,
              minX > 0 || minY > 0 || maxX < w - 1 || maxY < h - 1,
              let cropped = cg.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
        else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Downscales the image (widgets have tight memory and image-size
    /// limits) and saves it: PNG keeps transparency for icons, JPEG keeps
    /// photos small. Returns the new file name.
    static func save(_ data: Data, maxSide: CGFloat = 384, photo: Bool = false) -> String? {
        guard let source = UIImage(data: data), source.size.width > 0, source.size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(source.size.width, source.size.height))
        let size = CGSize(width: (source.size.width * scale).rounded(), height: (source.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = photo
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let draw: (UIGraphicsImageRendererContext) -> Void = { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        let encoded = photo ? renderer.jpegData(withCompressionQuality: 0.85, actions: draw) : renderer.pngData(actions: draw)
        let name = UUID().uuidString + (photo ? ".jpg" : ".png")
        do {
            try encoded.write(to: directory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func delete(_ name: String?) {
        guard let name else { return }
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}

/// A countdown's icon: its custom image or SF Symbol.
struct CountdownIcon: View {
    enum Style {
        /// Colored rounded-square badge (dropped when the countdown has no color).
        case badge
        /// Bare icon sitting on the countdown's own card background.
        case onCard
    }

    let countdown: Countdown
    var size: CGFloat
    var style: Style = .badge

    private var showsBadge: Bool { style == .badge && !countdown.isColorless }

    var body: some View {
        glyph
            // On cards, pin wide or short custom images to the top-left so
            // their visible top lines up with the text beside them.
            .frame(width: size * glyphScale, height: size * glyphScale,
                   alignment: style == .onCard ? .topLeading : .center)
            .frame(width: size, height: size)
            .background {
                if showsBadge {
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                        .fill(countdown.color.gradient)
                }
            }
    }

    private var customImage: UIImage? {
        countdown.iconFile.flatMap(IconStore.image)
    }

    private var glyphScale: CGFloat {
        if !showsBadge { return 1 }
        return customImage != nil ? 0.78 : 0.55
    }

    private var symbolColor: Color {
        switch style {
        case .badge: showsBadge ? .white : countdown.accent
        case .onCard: countdown.cardForeground
        }
    }

    @ViewBuilder private var glyph: some View {
        if let image = customImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: countdown.symbol)
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .foregroundStyle(symbolColor)
        }
    }
}

/// What sits behind a countdown's card or widget: its photo (dimmed, blurred
/// and faded toward the bottom so text stays readable) or its color.
struct CountdownBackground: View {
    let countdown: Countdown

    var body: some View {
        if let file = countdown.backgroundFile, let image = IconStore.image(file) {
            Color.black
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: countdown.blur, opaque: true)
                }
                .overlay { Color.black.opacity(countdown.dim) }
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.15), .clear, .black.opacity(0.5)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .clipped()
        } else {
            Rectangle().fill(countdown.cardBackground)
        }
    }
}
