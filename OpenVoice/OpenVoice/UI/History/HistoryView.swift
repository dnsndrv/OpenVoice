import AppKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var history: HistoryStore
    @State private var search = ""
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Очистить всё") { confirmClear = true }
            }
            .padding(12)

            Divider()

            if filtered.isEmpty {
                Spacer()
                Text("Пусто").foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filtered) { rec in
                    HistoryRow(record: rec)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                history.delete(rec)
                            } label: { Label("Удалить", systemImage: "trash") }
                        }
                }
                .listStyle(.plain)
                .clearScrollBackground()
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Поиск")
        .alert("Удалить всю историю?", isPresented: $confirmClear) {
            Button("Удалить", role: .destructive) { history.clear() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var filtered: [TranscriptionRecord] {
        if search.isEmpty { return history.recent }
        let q = search.lowercased()
        return history.recent.filter { $0.text.lowercased().contains(q) }
    }
}

struct HistoryRow: View {
    let record: TranscriptionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.1fс", record.durationSec))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.text, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Скопировать")
            }
            Text(record.text)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}
