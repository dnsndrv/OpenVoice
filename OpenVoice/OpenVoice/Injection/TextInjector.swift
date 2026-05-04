import AppKit
import ApplicationServices
import Foundation

/// Абстракция системного pasteboard для тестируемости.
protocol PasteboardProvider: AnyObject {
    var stringValue: String? { get set }
}

/// Абстракция отправки события Cmd+V для тестируемости.
protocol KeystrokePoster {
    func postCmdV() throws
}

final class TextInjector {
    enum InjectorError: Error, LocalizedError {
        case noAccessibility
        case eventCreationFailed

        var errorDescription: String? {
            switch self {
            case .noAccessibility: return "Нет разрешения на управление компьютером (Accessibility)"
            case .eventCreationFailed: return "Не удалось создать клавиатурное событие"
            }
        }
    }

    private let pasteboard: PasteboardProvider
    private let poster: KeystrokePoster
    private let trustChecker: () -> Bool
    private let restoreDelay: TimeInterval

    init(pasteboard: PasteboardProvider,
         poster: KeystrokePoster,
         trustChecker: @escaping () -> Bool,
         restoreDelay: TimeInterval = 0.5) {
        self.pasteboard = pasteboard
        self.poster = poster
        self.trustChecker = trustChecker
        self.restoreDelay = restoreDelay
    }

    /// Кладёт текст в pasteboard и шлёт Cmd+V в активное приложение.
    /// Через `restoreDelay` восстанавливает содержимое pasteboard, если
    /// `restorePasteboard == true`.
    func inject(_ text: String, restorePasteboard: Bool = true) async throws {
        guard trustChecker() else { throw InjectorError.noAccessibility }

        let saved = pasteboard.stringValue
        pasteboard.stringValue = text
        try poster.postCmdV()
        AppLog.inject.debug("posted Cmd+V (\(text.count, privacy: .public) chars)")

        guard restorePasteboard else { return }
        try? await Task.sleep(nanoseconds: UInt64(restoreDelay * 1_000_000_000))
        pasteboard.stringValue = saved
    }

    /// Опрашивает Accessibility-разрешение без интерактивного запроса.
    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// Запрашивает Accessibility-разрешение (показывает системный диалог).
    static func promptAccessibilityPermission() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts: CFDictionary = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}

// MARK: - System implementations

final class SystemPasteboard: PasteboardProvider {
    var stringValue: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set {
            NSPasteboard.general.clearContents()
            if let v = newValue {
                NSPasteboard.general.setString(v, forType: .string)
            }
        }
    }
}

final class CGEventKeystrokePoster: KeystrokePoster {
    private let vKeyCode: CGKeyCode = 9 // virtual key for "V"

    func postCmdV() throws {
        let src = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)
        else {
            throw TextInjector.InjectorError.eventCreationFailed
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
