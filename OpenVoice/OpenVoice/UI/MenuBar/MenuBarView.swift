import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var app: AppCoordinator
    @EnvironmentObject var recording: RecordingCoordinator
    @EnvironmentObject var history: HistoryStore
    @State private var showHistory = false
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                statusDot
                Text(statusText).font(.headline)
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Хоткей").font(.caption).foregroundStyle(.secondary)
                Text(app.settings.hotkeyKey.displayName)
                    .font(.system(.body, design: .monospaced))
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Последние").font(.caption).foregroundStyle(.secondary)
                if history.recent.isEmpty {
                    Text("Пока ничего не расшифровано")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(history.recent.prefix(3)) { rec in
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(rec.text, forType: .string)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                                Text(rec.text)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .font(.callout)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            HStack {
                Button("История…") { showHistory = true }
                Button("Настройки…") { showSettings = true }
                Spacer()
                Button("Выйти") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 320)
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(history)
                .frame(width: 520, height: 480)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(app)
                .frame(width: 480, height: 360)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
    }

    private var statusColor: Color {
        switch recording.state {
        case .idle: return .green
        case .recording: return .red
        case .transcribing, .injecting: return .blue
        case .error: return .yellow
        }
    }

    private var statusText: String {
        switch recording.state {
        case .idle: return "Готов"
        case .recording: return "Запись"
        case .transcribing: return "Расшифровка"
        case .injecting: return "Вставка"
        case .error(let m): return m
        }
    }
}
