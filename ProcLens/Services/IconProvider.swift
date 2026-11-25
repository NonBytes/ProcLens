import AppKit

final class IconProvider {
    static let shared = IconProvider()

    // Keep only display-sized bitmaps; NSWorkspace icons can carry large representations.
    private let cache = NSCache<NSString, NSImage>()
    private static let pixelSize = 80 // 40 points at 2x (the largest icon in the UI)
    private let genericIcon: NSImage

    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 8 * 1024 * 1024
        genericIcon = Self.thumbnail(NSWorkspace.shared.icon(forFile: "/usr/bin/env"))
    }

    private func icon(for path: String) -> NSImage {
        let components = (path as NSString).pathComponents
        let bundlePath = components.lastIndex { ($0 as NSString).pathExtension.lowercased() == "app" }
            .map { NSString.path(withComponents: Array(components[...$0])) }
        let iconPath = bundlePath ?? path
        let key = iconPath as NSString
        if let image = cache.object(forKey: key) { return image }
        return autoreleasepool {
            let image = Self.thumbnail(NSWorkspace.shared.icon(forFile: iconPath))
            cache.setObject(image, forKey: key, cost: Self.pixelSize * Self.pixelSize * 4)
            return image
        }
    }

    private static func thumbnail(_ source: NSImage) -> NSImage {
        let pixels = pixelSize
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return source }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
                    from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 40, height: 40))
        image.addRepresentation(bitmap)
        return image
    }

    func appIcon(for process: ProcessItem) -> NSImage {
        if !process.path.isEmpty {
            return icon(for: process.path)
        }
        if let app = NSRunningApplication(processIdentifier: process.pid), let img = app.icon {
            return Self.thumbnail(img)
        }
        return genericIcon
    }
}
