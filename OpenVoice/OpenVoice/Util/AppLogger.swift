import OSLog

enum AppLog {
    static let app = Logger(subsystem: "com.openvoice.app", category: "app")
    static let audio = Logger(subsystem: "com.openvoice.app", category: "audio")
    static let transcribe = Logger(subsystem: "com.openvoice.app", category: "transcribe")
    static let inject = Logger(subsystem: "com.openvoice.app", category: "inject")
    static let hotkey = Logger(subsystem: "com.openvoice.app", category: "hotkey")
    static let coord = Logger(subsystem: "com.openvoice.app", category: "coord")
}
