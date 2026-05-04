import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics
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
    var keyCode: Int64 {
        switch self {
        case .rightCommand: return Int64(kVK_RightCommand)
        case .rightOption: return Int64(kVK_RightOption)
        case .leftControl: return Int64(kVK_Control)
        case .fn: return Int64(kVK_Function)
        }
    }

    /// Битмаск из CGEventFlags для проверки «только эта клавиша зажата».
    var deviceFlag: CGEventFlags {
        switch self {
        case .rightCommand: return CGEventFlags(rawValue: 0x10)        // NX_DEVICERCMDKEYMASK
        case .rightOption: return CGEventFlags(rawValue: 0x40)         // NX_DEVICERALTKEYMASK
        case .leftControl: return CGEventFlags(rawValue: 0x01)         // NX_DEVICELCTLKEYMASK
        case .fn: return .maskSecondaryFn
        }
    }

    /// Логический модификатор для проверки «нет других зажатых».
    var logicalFlag: CGEventFlags {
        switch self {
        case .rightCommand: return .maskCommand
        case .rightOption: return .maskAlternate
        case .leftControl: return .maskControl
        case .fn: return .maskSecondaryFn
        }
    }
}

/// Глобальный монитор «нажатия и отпускания» одного модификатора без
/// сопровождающих клавиш — позволяет использовать клавиши вроде правого
/// Command как триггер. Срабатывает по отпусканию.
///
/// Под капотом — `CGEvent.tapCreate(.cgSessionEventTap, ...)`, это более
/// надёжный системный механизм, чем `NSEvent.addGlobalMonitor`.
final class ModifierHotkeyMonitor: ObservableObject {
    var onTrigger: (() -> Void)?

    /// Сколько `flagsChanged` событий получено с момента старта монитора.
    /// Полезно для диагностики: если 0 — значит trust не выдан / tap не
    /// активирован.
    @Published private(set) var eventCount: Int = 0
    @Published private(set) var isActive: Bool = false
    @Published private(set) var key: ModifierKey

    private var armed = false
    private var lastTrigger = Date.distantPast
    private let debounce: TimeInterval

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(key: ModifierKey, debounce: TimeInterval = 0.15) {
        self.key = key
        self.debounce = debounce
    }

    deinit { stop() }

    func start() {
        stop()

        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: userInfo
        ) else {
            AppLog.hotkey.error("CGEvent.tapCreate failed — Accessibility not granted?")
            isActive = false
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = runLoopSource
        self.isActive = true
        AppLog.hotkey.info("CGEventTap installed, key=\(self.key.rawValue, privacy: .public)")
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        armed = false
        isActive = false
    }

    func setKey(_ newKey: ModifierKey) {
        guard newKey != key else { return }
        key = newKey
        armed = false
        if isActive { start() }
    }

    fileprivate func handle(event: CGEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.eventCount += 1
        }

        let type = event.type
        if type == .keyDown {
            armed = false
            return
        }
        guard type == .flagsChanged else { return }

        let kc = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if kc == key.keyCode {
            // Зажат ли наш модификатор (по device-флагу) и нет ли других
            // логических модификаторов кроме нашего?
            let pressed = flags.contains(key.deviceFlag)
            let otherLogical = flags
                .intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
                .subtracting(key.logicalFlag)
            let exclusive = otherLogical.isEmpty

            if pressed && exclusive {
                armed = true
            } else if !pressed {
                if armed {
                    armed = false
                    let now = Date()
                    if now.timeIntervalSince(lastTrigger) >= debounce {
                        lastTrigger = now
                        AppLog.hotkey.debug("Hotkey trigger")
                        DispatchQueue.main.async { [weak self] in
                            self?.onTrigger?()
                        }
                    }
                }
            }
        } else {
            // Любая другая клавиша/модификатор сбивает «armed».
            if type == .flagsChanged && flags
                .intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn])
                .subtracting(key.logicalFlag) != [] {
                armed = false
            }
        }
    }
}

/// C-callback для CGEventTap. Распаковывает userInfo обратно в монитор.
private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let refcon {
            let monitor = Unmanaged<ModifierHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async { monitor.start() }
        }
        return Unmanaged.passUnretained(event)
    }
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<ModifierHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.handle(event: event)
    return Unmanaged.passUnretained(event)
}
