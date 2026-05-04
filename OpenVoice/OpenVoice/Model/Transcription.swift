import Foundation
import SwiftData

@Model
final class TranscriptionRecord {
    @Attribute(.unique) var id: UUID
    var text: String
    var durationSec: Double
    var createdAt: Date
    var language: String

    init(id: UUID = UUID(),
         text: String,
         durationSec: Double,
         createdAt: Date = Date(),
         language: String) {
        self.id = id
        self.text = text
        self.durationSec = durationSec
        self.createdAt = createdAt
        self.language = language
    }
}
