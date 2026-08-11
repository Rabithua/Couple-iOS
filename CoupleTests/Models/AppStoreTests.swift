import Testing
@testable import Couple

@MainActor
struct AppStoreTests {
    @Test("Past filters do not replace the home note collection")
    func pastFiltersDoNotReplaceHomeNotes() async {
        let store = AppStore(
            environment: ["COUPLE_DEMO_MODE": "1"],
            arguments: ["CoupleTests"]
        )
        await store.start()
        let homeNotes = store.notes

        await store.selectNotes(.photos)

        #expect(store.notes == homeNotes)
        #expect(store.pastNotes.count < homeNotes.count)
        #expect(store.pastNotes.allSatisfy { note in
            note.attachments.contains(where: \.isImage)
        })
    }

    @Test("Past page caches stay independent")
    func pastPageCachesStayIndependent() async {
        let store = AppStore(
            environment: ["COUPLE_DEMO_MODE": "1"],
            arguments: ["CoupleTests"]
        )
        await store.start()

        let photoNotes = store.pastNotes(for: .photos)
        await store.selectNotes(.completedTodos)

        #expect(!photoNotes.isEmpty)
        #expect(photoNotes.allSatisfy { $0.attachments.contains(where: \.isImage) })
        #expect(store.pastNotes.allSatisfy { $0.todoId != nil })
        #expect(store.pastNotes(for: .photos) == photoNotes)
    }
}
