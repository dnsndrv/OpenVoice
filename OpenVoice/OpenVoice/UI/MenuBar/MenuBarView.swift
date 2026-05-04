import AppKit
import AVFoundation
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var app: AppCoordinator
    @EnvironmentObject var recording: RecordingCoordinator
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var models: ModelManager

    var body: some View {
        ZStack {
            GlassBackground(material: .popover, blending: .behindWindow)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                statusCard
                hotkeyRow
                if case .downloading(let progress) = models.state {
                    downloadCard(progress: progress)
                }
                recentSection
                Spacer(minLength: 0)
                actionRow
            }
            .padding(16)
        }
        .frame(width: 340, height: 380)
    }

    private func downloadCard(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint)
                Text("Скачивается модель")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress).tint(.accentColor)
            HStack {
                Text(downloadingModelName)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Отмена") { models.cancel() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var downloadingModelName: String {
        models.activeDownload?.displayName ?? ""
    }

    // MARK: - Status

    private var statusCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(statusColor.opacity(0.18)).frame(width: 36, height: 36)
                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle).font(.system(size: 14, weight: .semibold))
                Text(statusSubtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { recording.toggle() }) {
                Image(systemName: recording.state == .idle ? "record.circle" : "stop.circle.fill")
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .help(recording.state == .idle ? "Записать" : "Остановить")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var hotkeyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard").foregroundStyle(.secondary)
            Text(app.settings.hotkeyKey.displayName)
                .font(.system(.callout, design: .rounded).weight(.medium))
            Text("·").foregroundStyle(.secondary)
            Text("одиночный модификатор-toggle")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Circle()
                .fill(app.hotkeyMonitor.isActive ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
                .help(app.hotkeyMonitor.isActive ? "Мониторинг активен" : "Мониторинг остановлен")
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Последние").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !history.recent.isEmpty {
                    Button("Все") { openHistory() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            if history.recent.isEmpty {
                HStack {
                    Image(systemName: "tray").foregroundStyle(.secondary)
                    Text("Пока ничего не расшифровано")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(history.recent.prefix(3)) { rec in
                        RecentRow(record: rec)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 6) {
            actionButton(systemName: "clock", label: "История") { openHistory() }
            actionButton(systemName: "gearshape", label: "Настройки") { openSettings() }
            actionButton(systemName: "book", label: "Словарь") { openDictionary() }
            actionButton(systemName: "stethoscope", label: "Диагностика") { openDiagnostics() }
            Spacer()
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Выйти")
        }
        .padding(.horizontal, 4)
    }

    private func actionButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemName).font(.system(size: 14))
                Text(label).font(.system(size: 9))
            }
            .frame(width: 56, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - Status mapping

    private var statusColor: Color {
        switch recording.state {
        case .idle: return .accentColor
        case .recording: return .red
        case .transcribing, .injecting: return .blue
        case .error: return .orange
        }
    }

    private var statusIcon: String {
        switch recording.state {
        case .idle: return "mic.fill"
        case .recording: return "waveform"
        case .transcribing: return "text.bubble.fill"
        case .injecting: return "text.cursor"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var statusTitle: String {
        switch recording.state {
        case .idle: return "Готов"
        case .recording: return "Идёт запись"
        case .transcribing: return "Расшифровка"
        case .injecting: return "Вставка"
        case .error: return "Ошибка"
        }
    }

    private var statusSubtitle: String {
        switch recording.state {
        case .idle:
            return app.accessibilityGranted ? "Жми хоткей или кнопку справа" : "Выдай Accessibility в Настройках"
        case .recording:
            return "Нажми хоткей ещё раз, чтобы остановить"
        case .transcribing:
            return "Whisper обрабатывает аудио"
        case .injecting:
            return "Текст вставляется в активное приложение"
        case .error(let m):
            return m
        }
    }

    // MARK: - Window openers

    private func openHistory() {
        let history = self.history
        WindowOpener.shared.open(id: "history", title: "История",
                                  size: NSSize(width: 560, height: 540)) {
            HistoryView().environmentObject(history)
        }
    }

    private func openSettings() {
        let app = self.app
        let models = self.models
        WindowOpener.shared.open(id: "settings", title: "Настройки",
                                  size: NSSize(width: 540, height: 560)) {
            SettingsView()
                .environmentObject(app)
                .environmentObject(models)
        }
    }

    private func openDictionary() {
        let dict = app.dictionary
        WindowOpener.shared.open(id: "dictionary", title: "Словарь замен",
                                  size: NSSize(width: 600, height: 500)) {
            DictionarySettingsView(dictionary: dict)
        }
    }

    private func openDiagnostics() {
        let app = self.app
        WindowOpener.shared.open(id: "diagnostics", title: "Диагностика",
                                  size: NSSize(width: 600, height: 480)) {
            DiagnosticsView().environmentObject(app)
        }
    }
}

// MARK: - Recent row

private struct RecentRow: View {
    let record: TranscriptionRecord
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(record.text, forType: .string)
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation { copied = false }
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(copied ? .green : .secondary)
                    .font(.system(size: 12))
                    .padding(.top, 2)
                Text(record.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .font(.callout)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
