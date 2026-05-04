import AppKit
import Carbon.HIToolbox
import Foundation

/// Один из четырёх модификаторов, которые можно использовать как одиночный
/// триггер.
enum ModifierKey: String, CaseIterable, Identifiable, Codable {
    case rightCommand
    case rightOption
    case leftControl
    case fn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rightCommand: return "Правый ⌘"
        case .rightOption: return "Правый ⌥"
        case .leftControl: return "Левый ⌃"
        case .fn: return "Fn"
        }
    }

    /// virtual key codes (Carbon)
    var keyCode: UInt16 {
        switch self {
        case .rightCommand: return UInt16(kVK_RightCommand)
        case .rightOption: return UInt16(kVK_RightOption)
        case .leftControl: return UInt16(kVK_Control)
        case .fn: return UInt16(kVK_Function)
        }
    }
}

/// Глобальный монитор «нажатия и отпускания» одного модификатора без
/// сопровождающих клавиш — это позволяет использовать клавиши вроде
/// правого Command как триггер диктовки. Срабатывает по отпусканию.
///
/// Алгоритм:
/// - При получении flagsChanged с keyCode целевой клавиши: если этот
///   модификатор зажат и кроме него нет других — «armed=true».
/// - Если зажимают другой модификатор или нажимают обычную клавишу —
///   armed=false (значит пользователь набирал сочетание).
/// - Когда модификатор отпускают и armed=true — триггер.
final class ModifierHotkeyMonitor {
    var onTrigger: (() -> Void)?

    private(set) var key: ModifierKey
    private var armed = false
    private var lastTrigger = Date.distantPast
    private let debounce: TimeInterval

    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(key: ModifierKey, debounce: TimeInterval = 0.15) {
        self.key = key
        self.debounce = debounce
    }

    deinit { stop() }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event: event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event: event)
            return event
        }
        AppLog.hotkey.info("Hotkey monitor started, key=\(self.key.rawValue, privacy: .public)")
    }

    func stop() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor { NSEvent.removeMonitor(l); localMonitor = nil }
        armed = false
    }

    func setKey(_ newKey: ModifierKey) {
        guard newKey != key else { return }
        key = newKey
        armed = false
        if globalMonitor != nil { start() }
    }

    /// Internal handler — вынесен наружу для unit-тестов.
    func handle(event: NSEvent) {
        if event.type == .keyDown {
            armed = false
            return
        }
        guard event.type == .flagsChanged else { return }

        let kc = event.keyCode
        let flags = event.modifierFlags

        if kc == key.keyCode {
            let isPressed = flags.contains(modifierFlag(for: key)) && isExclusive(flags: flags, for: key)
            if isPressed {
                armed = true
            } else {
                if armed {
                    armed = false
                    let now = Date()
                    if now.timeIntervalSince(lastTrigger) >= debounce {
                        lastTrigger = now
                        AppLog.hotkey.debug("Hotkey trigger")
                        onTrigger?()
                    }
                }
            }
        } else {
            armed = false
        }
    }

    private func modifierFlag(for key: ModifierKey) -> NSEvent.ModifierFlags {
        switch key {
        case .rightCommand: return .command
        case .rightOption: return .option
        case .leftControl: return .control
        case .fn: return .function
        }
    }

    /// Проверяет что зажат только один логический модификатор.
    /// Для Fn мы дополнительно требуем отсутствие других стандартных модификаторов.
    private func isExclusive(flags: NSEvent.ModifierFlags, for key: ModifierKey) -> Bool {
        let allMods: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let pressed = flags.intersection(allMods)
        let target = modifierFlag(for: key).intersection(allMods)
        return pressed == target
    }
}
