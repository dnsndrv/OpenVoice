import SwiftUI

/// Редактор словаря замен. Левая колонка — что услышал whisper, правая —
/// чем заменить. Чекбокс «Aa» включает чувствительность к регистру.
struct DictionarySettingsView: View {
    @ObservedObject var dictionary: CustomDictionary
    @State private var selection: UUID?
    @State private var draftPattern: String = ""
    @State private var draftReplacement: String = ""
    @State private var draftCaseSensitive: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            addRow
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Словарь замен").font(.headline)
                Text("Применяется к расшифровке перед вставкой. Совпадение ищется по целым словам.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var list: some View {
        Group {
            if dictionary.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("Пока пусто. Добавь первую замену снизу.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
                    .frame(minHeight: 240)
                    .clearScrollBackground()
            }
        }
    }

    private var table: some View {
        Table(dictionary.entries, selection: $selection) {
            TableColumn("Услышал") { e in
                TextField("", text: binding(for: e, keyPath: \.pattern))
                    .textFieldStyle(.plain)
            }
            TableColumn("Заменить на") { e in
                TextField("", text: binding(for: e, keyPath: \.replacement))
                    .textFieldStyle(.plain)
            }
            TableColumn("Aa") { e in
                Toggle("", isOn: binding(for: e, keyPath: \.caseSensitive))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .width(36)
            TableColumn("") { e in
                Button {
                    dictionary.delete(id: e.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .width(28)
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("Услышал (например, «джипити»)", text: $draftPattern)
                .textFieldStyle(.roundedBorder)
            Text("→").foregroundStyle(.secondary)
            TextField("Заменить на (например, «GPT»)", text: $draftReplacement)
                .textFieldStyle(.roundedBorder)
            Toggle("Aa", isOn: $draftCaseSensitive)
                .toggleStyle(.checkbox)
                .help("Учитывать регистр")
            Button("Добавить") {
                let p = draftPattern.trimmingCharacters(in: .whitespacesAndNewlines)
                let r = draftReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !p.isEmpty else { return }
                dictionary.add(DictionaryEntry(pattern: p, replacement: r, caseSensitive: draftCaseSensitive))
                draftPattern = ""
                draftReplacement = ""
                draftCaseSensitive = false
            }
            .keyboardShortcut(.defaultAction)
            .disabled(draftPattern.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Двусторонний биндинг к полю записи в массиве: чтение читает текущий
    /// snapshot, запись находит запись по id и применяет update.
    private func binding<Value>(
        for entry: DictionaryEntry,
        keyPath: WritableKeyPath<DictionaryEntry, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                guard let current = dictionary.entries.first(where: { $0.id == entry.id }) else {
                    return entry[keyPath: keyPath]
                }
                return current[keyPath: keyPath]
            },
            set: { newValue in
                guard var current = dictionary.entries.first(where: { $0.id == entry.id }) else { return }
                current[keyPath: keyPath] = newValue
                dictionary.update(current)
            }
        )
    }
}
