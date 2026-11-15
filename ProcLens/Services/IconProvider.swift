import AppKit

final class IconProvider {
    static let shared = IconProvider()

    private var cache: [String: NSImage] = [:]
    private let genericIcon: NSImage

    private init() {
        genericIcon = NSWorkspace.shared.icon(forFile: "/usr/bin/env")
    }

    private func icon(for path: String) -> NSImage {
        if let cached = cache[path] {
            return cached
        }

        let components = (path as NSString).pathComponents
        let bundlePath = components.lastIndex { ($0 as NSString).pathExtension.lowercased() == "app" }
            .map { NSString.path(withComponents: Array(components[...$0])) }
        let iconPath = bundlePath ?? path
        let image = cache[iconPath] ?? NSWorkspace.shared.icon(forFile: iconPath)
        cache[iconPath] = image
        cache[path] = image
        return image
    }

    func appIcon(for process: ProcessItem) -> NSImage {
        if !process.path.isEmpty {
            return icon(for: process.path)
        }
        if let app = NSRunningApplication(processIdentifier: process.pid), let img = app.icon {
            return img
        }
        return genericIcon
    }
}
