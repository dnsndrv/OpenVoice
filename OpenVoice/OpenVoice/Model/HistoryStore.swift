import Foundation
import SwiftData

@MainActor
final class HistoryStore: ObservableObject {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    /// Список последних N записей. Обновляется после каждого save/delete.
    @Published private(set) var recent: [TranscriptionRecord] = []

    init(inMemory: Bool = false) {
        let schema = Schema([TranscriptionRecord.self])
        let config = ModelConfiguration("OpenVoiceHistory",
                                        schema: schema,
                                        isStoredInMemoryOnly: inMemory)
        do {
            self.container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        refresh()
    }

    func save(text: String, durationSec: Double, language: String) {
        let record = TranscriptionRecord(text: text, durationSec: durationSec, language: language)
        context.insert(record)
        try? context.save()
        refresh()
    }

    func delete(_ record: TranscriptionRecord) {
        context.delete(record)
        try? context.save()
        refresh()
    }

    func clear() {
        try? context.delete(model: TranscriptionRecord.self)
        try? context.save()
        refresh()
    }

    func refresh(limit: Int = 100) {
        var descriptor = FetchDescriptor<TranscriptionRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        recent = (try? context.fetch(descriptor)) ?? []
    }
}
