import AppKit
import AVFoundation
import ApplicationServices
import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var app: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Диагностика").font(.title3).bold()
                Spacer()
                Button("Скопировать") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
                Button("Закрыть") { dismiss() }
            }
            .padding(12)

            Divider()

            ScrollView {
                Text(report)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
    }

    private var report: String {
        let bundle = Bundle.main
        let bundleId = bundle.bundleIdentifier ?? "?"
        let bundlePath = bundle.bundlePath
        let exec = bundle.executableURL?.path ?? "?"
        let micStatus: String = {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined: return "notDetermined"
            case .restricted: return "restricted"
            case .denied: return "denied"
            case .authorized: return "authorized"
            @unknown default: return "unknown"
            }
        }()
        let axTrusted = AXIsProcessTrusted()
        let monitor = "active=\(app.hotkeyMonitor.isActive) events=\(app.hotkeyMonitor.eventCount) key=\(app.hotkeyMonitor.key.rawValue)"
        let modelDir = ModelManager.modelsDirectory.path
        let smallModel = ModelManager.modelsDirectory.appendingPathComponent("ggml-small.bin").path
        let smallExists = FileManager.default.fileExists(atPath: smallModel)

        return """
        Bundle ID:        \(bundleId)
        Bundle path:      \(bundlePath)
        Executable:       \(exec)
        Microphone:       \(micStatus)
        Accessibility:    \(axTrusted ? "trusted" : "NOT trusted")
        Hotkey monitor:   \(monitor)
        Models dir:       \(modelDir)
        ggml-small.bin:   \(smallExists ? "present" : "missing")
        Recording state:  \(String(describing: app.recording.state))
        macOS:            \(ProcessInfo.processInfo.operatingSystemVersionString)
        """
    }
}
