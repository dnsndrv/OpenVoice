import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppCoordinator
    @EnvironmentObject var models: ModelManager
    @State private var hotkey: ModifierKey = .rightCommand
    @State private var language: String = "ru"
    @State private var restorePasteboard: Bool = true
    @State private var hasAccessibility: Bool = TextInjector.hasAccessibilityPermission()
    @State private var selectedModel: ModelManager.ModelName = .small

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Хоткей") {
                    Picker("Клавиша", selection: $hotkey) {
                        ForEach(ModifierKey.allCases) { k in
                            Text(k.displayName).tag(k)
                        }
                    }
                    .onChange(of: hotkey) { _, new in app.updateHotkey(new) }
                    Text("Нажми и отпусти выбранный модификатор без других клавиш — начнётся запись. Ещё раз — остановит и вставит текст.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Модель") {
                    Picker("Модель", selection: $selectedModel) {
                        ForEach(ModelManager.ModelName.allCases) { m in
                            HStack {
                                Text(m.displayName)
                                if models.isDownloaded(m) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                            .tag(m)
                        }
                    }
                    modelStateRow
                }

                Section("Язык") {
                    Picker("Язык", selection: $language) {
                        Text("Русский").tag("ru")
                        Text("English").tag("en")
                        Text("Авто").tag("auto")
                    }
                    .onChange(of: language) { _, new in app.settings.language = new }
                }

                Section("Pasteboard") {
                    Toggle("Восстанавливать после вставки", isOn: $restorePasteboard)
                        .onChange(of: restorePasteboard) { _, new in app.settings.restorePasteboard = new }
                }

                Section("Словарь замен") {
                    HStack {
                        Text(app.dictionary.entries.isEmpty
                             ? "Замен пока нет"
                             : "Замен: \(app.dictionary.entries.count)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Открыть…") {
                            WindowOpener.shared.open(id: "dictionary", title: "Словарь замен",
                                                      size: NSSize(width: 580, height: 480)) {
                                DictionarySettingsView(dictionary: app.dictionary)
                            }
                        }
                    }
                }

                Section("Разрешения") {
                    HStack {
                        Image(systemName: hasAccessibility ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(hasAccessibility ? .green : .orange)
                        Text(hasAccessibility ? "Accessibility разрешён" : "Accessibility не выдан")
                        Spacer()
                        Button("Открыть настройки") {
                            TextInjector.promptAccessibilityPermission()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Button("Проверить") {
                            hasAccessibility = TextInjector.hasAccessibilityPermission()
                        }
                    }
                }

                Section("Диагностика") {
                    HStack {
                        Text("Системная информация и состояние компонентов")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Открыть…") {
                            WindowOpener.shared.open(id: "diagnostics", title: "Диагностика",
                                                      size: NSSize(width: 600, height: 480)) {
                                DiagnosticsView().environmentObject(app)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .clearScrollBackground()
            .padding(8)
        }
        .frame(minWidth: 480, minHeight: 460)
        .onAppear {
            hotkey = app.settings.hotkeyKey
            language = app.settings.language
            restorePasteboard = app.settings.restorePasteboard
            hasAccessibility = TextInjector.hasAccessibilityPermission()
            selectedModel = ModelManager.ModelName(rawValue: app.settings.modelName) ?? .small
        }
    }

    @ViewBuilder
    private var modelStateRow: some View {
        switch models.state {
        case .absent, .ready, .failed:
            HStack {
                if models.isDownloaded(selectedModel) {
                    Label("Модель скачана", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Использовать") {
                        Task { await app.loadModel(selectedModel) }
                    }
                } else {
                    Text("Модель не скачана").foregroundStyle(.secondary)
                    Spacer()
                    Button("Скачать") {
                        Task { await app.loadModel(selectedModel) }
                    }
                }
            }
            if case .failed(let msg) = models.state {
                Text(msg).font(.caption).foregroundStyle(.red)
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Качаю \(selectedModel.displayName)")
                        .font(.callout)
                    Spacer()
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.callout).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
                HStack {
                    Text("Файл сохранится в ~/Library/Application Support/VibeVoice/models")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Отмена") { models.cancel() }
                        .controlSize(.small)
                }
            }
        }
    }
}
