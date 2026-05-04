import Foundation
import SwiftUI

final class SettingsStore: ObservableObject {
    @AppStorage("hotkeyKey") var hotkeyKeyRaw: String = ModifierKey.rightCommand.rawValue
    @AppStorage("language") var language: String = "ru"
    @AppStorage("modelName") var modelName: String = "small"
    @AppStorage("restorePasteboard") var restorePasteboard: Bool = true

    var hotkeyKey: ModifierKey {
        get { ModifierKey(rawValue: hotkeyKeyRaw) ?? .rightCommand }
        set { hotkeyKeyRaw = newValue.rawValue }
    }
}
