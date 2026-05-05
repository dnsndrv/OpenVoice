import OSLog

enum AppLog {
    static let app = Logger(subsystem: "com.vibevoice.app", category: "app")
    static let audio = Logger(subsystem: "com.vibevoice.app", category: "audio")
    static let transcribe = Logger(subsystem: "com.vibevoice.app", category: "transcribe")
    static let inject = Logger(subsystem: "com.vibevoice.app", category: "inject")
    static let hotkey = Logger(subsystem: "com.vibevoice.app", category: "hotkey")
    static let coord = Logger(subsystem: "com.vibevoice.app", category: "coord")
}
