import Testing
import Foundation
@testable import OpenVoice

// MARK: - TextInjector

final class MockPasteboard: PasteboardProvider {
    var stringValue: String?
    var history: [String?] = []
    init(initial: String? = nil) {
        stringValue = initial
        history.append(initial)
    }
}

final class MockPoster: KeystrokePoster {
    var posted = 0
    var error: Error?
    func postCmdV() throws {
        if let error { throw error }
        posted += 1
    }
}

@Suite struct TextInjectorTests {
    @Test func injectPlacesTextThenRestores() async throws {
        let pb = MockPasteboard(initial: "old")
        let poster = MockPoster()
        let injector = TextInjector(
            pasteboard: pb,
            poster: poster,
            trustChecker: { true },
            restoreDelay: 0.05
        )
        try await injector.inject("привет")
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(poster.posted == 1)
        #expect(pb.stringValue == "old")
    }

    @Test func injectNoRestore() async throws {
        let pb = MockPasteboard(initial: "old")
        let injector = TextInjector(
            pasteboard: pb,
            poster: MockPoster(),
            trustChecker: { true },
            restoreDelay: 0.05
        )
        try await injector.inject("новое", restorePasteboard: false)
        #expect(pb.stringValue == "новое")
    }

    @Test func injectFailsWithoutAccessibility() async {
        let injector = TextInjector(
            pasteboard: MockPasteboard(),
            poster: MockPoster(),
            trustChecker: { false }
        )
        await #expect(throws: TextInjector.InjectorError.self) {
            try await injector.inject("x")
        }
    }
}

// MARK: - RecordingCoordinator

struct RecordingTranscriber: Transcribing {
    let result: String
    let delay: UInt64
    let error: Error?
    init(result: String = "result", delay: UInt64 = 50_000_000, error: Error? = nil) {
        self.result = result; self.delay = delay; self.error = error
    }
    func transcribe(pcm: Data, language: String) async throws -> String {
        try await Task.sleep(nanoseconds: delay)
        if let error { throw error }
        return result
    }
}

@MainActor
@Suite struct HistoryStoreTests {
    @Test func saveAndRecent() {
        let store = HistoryStore(inMemory: true)
        store.save(text: "first", durationSec: 1, language: "ru")
        store.save(text: "second", durationSec: 2, language: "ru")
        #expect(store.recent.count == 2)
        #expect(store.recent.first?.text == "second")
    }

    @Test func clear() {
        let store = HistoryStore(inMemory: true)
        store.save(text: "a", durationSec: 1, language: "ru")
        store.clear()
        #expect(store.recent.isEmpty)
    }
}
