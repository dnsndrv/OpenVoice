import AppKit
import SwiftUI

/// Открывает SwiftUI-вью в отдельном NSWindow и держит у себя ссылку,
/// чтобы окно не схлопнулось.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    private var openWindows: [String: NSWindow] = [:]

    func open<V: View>(
        id: String,
        title: String,
        size: NSSize = NSSize(width: 520, height: 480),
        @ViewBuilder content: () -> V
    ) {
        if let existing = openWindows[id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // Стандартный системный titlebar — кнопки управления и заголовок
        // должны быть видны. Glass-материал ограничиваем зоной контента.
        let rootView = content()
            .background(GlassBackground(material: .windowBackground, blending: .behindWindow))
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.titleVisibility = .visible
        window.setContentSize(size)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = WindowOpenerDelegate.shared

        openWindows[id] = window
        WindowOpenerDelegate.shared.onClose[ObjectIdentifier(window)] = { [weak self] in
            self?.openWindows.removeValue(forKey: id)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Глобальный делегат, ловит закрытие окон и удаляет их из словаря.
@MainActor
final class WindowOpenerDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowOpenerDelegate()
    var onClose: [ObjectIdentifier: () -> Void] = [:]

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let id = ObjectIdentifier(window)
        onClose[id]?()
        onClose.removeValue(forKey: id)
    }
}
