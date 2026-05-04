import Combine
import Foundation

/// Пользовательский словарь замен. Применяется к расшифровке whisper'а
/// перед вставкой: помогает поправить термины, имена, аббревиатуры,
/// которые модель стабильно слышит криво (например, «джипити» → «GPT»).
struct DictionaryEntry: Identifiable, Codable, Hashable {
    var id: UUID
    /// Что искать. Сравнение идёт по словам (\b границы); регистр зависит
    /// от `caseSensitive`.
    var pattern: String
    /// На что заменять.
    var replacement: String
    /// Если true — точное совпадение регистра. Иначе любые регистры.
    var caseSensitive: Bool

    init(id: UUID = UUID(), pattern: String, replacement: String, caseSensitive: Bool = false) {
        self.id = id
        self.pattern = pattern
        self.replacement = replacement
        self.caseSensitive = caseSensitive
    }
}

/// Хранит список замен в `UserDefaults` (ключ `customDictionary`),
/// публикует изменения через `@Published` для подписки UI/координатора.
@MainActor
final class CustomDictionary: ObservableObject {
    @Published private(set) var entries: [DictionaryEntry]

    private let defaults: UserDefaults
    private let key = "customDictionary"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = []
        }
    }

    func add(_ entry: DictionaryEntry) {
        entries.append(entry)
        persist()
    }

    func update(_ entry: DictionaryEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
        persist()
    }

    func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        persist()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }

    /// Применяет все правила по порядку. Если `pattern` пустой — пропускаем.
    /// Совпадение ищется по границам слов (`\b`), что предохраняет от
    /// «GPT» внутри «GPTeam». Для кириллицы `\b` тоже работает: NSRegularExpression
    /// использует `UWORD`-классы.
    func apply(to text: String) -> String {
        guard !entries.isEmpty else { return text }
        var result = text
        for entry in entries where !entry.pattern.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: entry.pattern)
            let pattern = "\\b\(escaped)\\b"
            var options: NSRegularExpression.Options = []
            if !entry.caseSensitive { options.insert(.caseInsensitive) }
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            // `$0` в шаблоне замены не нужно — заменяем целиком.
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: entry.replacement)
            )
        }
        return result
    }
}
