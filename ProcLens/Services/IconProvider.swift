import AppKit

final class IconProvider {
    static let shared = IconProvider()

    private var cache: [String: NSImage] = [:]
    private let genericIcon: NSImage

    private init() {
        genericIcon = NSWorkspace.shared.icon(forFile: "/usr/bin/env")
        genericIcon.size = NSSize(width: 16, height: 16)
    }

    func icon(for path: String) -> NSImage {
        guard !path.isEmpty else { return genericIcon }
        if let cached = cache[path] {
            return cached
        }
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: 16, height: 16)
        cache[path] = img
        return img
    }

    func appIcon(for process: ProcessItem) -> NSImage {
        if !process.path.isEmpty {
            return icon(for: process.path)
        }
        if let app = NSRunningApplication(processIdentifier: process.pid), let img = app.icon {
            img.size = NSSize(width: 16, height: 16)
            return img
        }
        return genericIcon
    }
}
