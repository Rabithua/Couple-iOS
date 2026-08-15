import Foundation
import SwiftData
import Testing
@testable import Couple

@MainActor
struct ReviewFeedbackTests {
    @Test("Editing a yearly occurrence preserves its canonical anchor")
    func yearlyOccurrencePreservesCanonicalAnchor() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let calendar = utcCalendar()
        let sourceStart = try #require(calendar.date(from: DateComponents(
            year: 2020,
            month: 8,
            day: 15,
            hour: 10
        )))
        let sourceEnd = sourceStart.addingTimeInterval(3_600)
        let source = try store.createCalendarEvent(
            coupleId: "couple",
            ownerId: "owner",
            title: "年度日程",
            start: sourceStart,
            end: sourceEnd,
            allDay: false,
            yearly: true
        )
        let rangeStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let rangeEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31)))
        let occurrence = try #require(CalendarOccurrenceExpander.expand(
            canonicalEvents: [source],
            from: rangeStart,
            to: rangeEnd,
            calendar: calendar
        ).first)

        try store.editCalendarEvent(
            id: source.id,
            title: "只改标题",
            start: occurrence.startTime,
            end: occurrence.endTime,
            allDay: occurrence.allDay,
            occurrenceStart: occurrence.startTime,
            occurrenceEnd: occurrence.endTime
        )

        let canonical = try #require(try await store.loadSnapshot().canonicalCalendarEvents.first)
        #expect(canonical.title == "只改标题")
        #expect(canonical.startTime == sourceStart)
        #expect(canonical.endTime == sourceEnd)
    }

    @Test("Occurrence time changes map back to the series and preserve optional ends")
    func yearlyOccurrenceMapsRelativeTimeChanges() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceStart = Date(timeIntervalSince1970: 1_597_482_000)
        let source = try store.createCalendarEvent(
            coupleId: "couple",
            ownerId: "owner",
            title: "无结束时间",
            start: sourceStart,
            end: nil,
            allDay: false,
            yearly: true
        )
        let occurrenceStart = sourceStart.addingTimeInterval(365 * 6 * 86_400)
        let editedStart = occurrenceStart.addingTimeInterval(2 * 86_400)

        try store.editCalendarEvent(
            id: source.id,
            title: source.title,
            start: editedStart,
            end: nil,
            allDay: false,
            occurrenceStart: occurrenceStart,
            occurrenceEnd: nil
        )
        var canonical = try #require(try await store.loadSnapshot().canonicalCalendarEvents.first)
        #expect(canonical.startTime == sourceStart.addingTimeInterval(2 * 86_400))
        #expect(canonical.endTime == nil)

        try store.editCalendarEvent(
            id: source.id,
            title: source.title,
            start: editedStart,
            end: editedStart.addingTimeInterval(7_200),
            allDay: false,
            occurrenceStart: editedStart,
            occurrenceEnd: nil
        )
        canonical = try #require(try await store.loadSnapshot().canonicalCalendarEvents.first)
        #expect(canonical.endTime == canonical.startTime.addingTimeInterval(7_200))
    }

    @Test("Calendar editor preserves optional ends and duration")
    func calendarEditorPreservesOptionalEndsAndDuration() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let start = Date(timeIntervalSince1970: 1_597_482_000)
        let event = try store.createCalendarEvent(
            coupleId: "couple",
            ownerId: "owner",
            title: "无结束时间",
            start: start,
            end: nil,
            allDay: false,
            yearly: false
        )

        #expect(NewCalendarEventView.initiallyHasEndTime(editing: nil))
        #expect(!NewCalendarEventView.initiallyHasEndTime(editing: event))
        #expect(NewCalendarEventView.defaultEnd(after: start) == start.addingTimeInterval(3_600))

        let shifted = NewCalendarEventView.shiftedEnd(
            oldStart: start,
            newStart: start.addingTimeInterval(1_800),
            currentEnd: start.addingTimeInterval(7_200)
        )
        #expect(shifted == start.addingTimeInterval(9_000))
    }

    @Test("Home anniversary matching ignores ID case and retains cached fallback")
    func homeAnniversaryMatchesCaseInsensitivelyAndFallsBack() async {
        let store = AppStore(
            environment: ["COUPLE_DEMO_MODE": "1"],
            arguments: ["CoupleTests"]
        )
        await store.start()
        let local = anniversary(id: "abc-def", title: "本地纪念日", daysFromNow: 2)
        let cached = anniversary(id: "ABC-DEF", title: "缓存纪念日", daysFromNow: 2)
        store.anniversaries = [local]
        store.home = home(nextAnniversary: cached)

        #expect(store.homeAnniversary?.title == "本地纪念日")
        store.anniversaries = []
        #expect(store.homeAnniversary?.title == "缓存纪念日")
    }

    @Test("Deleting the cached home anniversary selects the next actual occurrence")
    func deletingHomeAnniversarySelectsNextOccurrence() async throws {
        let store = AppStore(
            environment: ["COUPLE_DEMO_MODE": "1"],
            arguments: ["CoupleTests"]
        )
        await store.start()
        let first = anniversary(id: "first", title: "最近", daysFromNow: 1)
        let second = anniversary(id: "second", title: "下一个", daysFromNow: 3)
        store.anniversaries = [second, first]
        store.home = home(nextAnniversary: first)

        try await store.deleteAnniversary(first)

        #expect(store.homeAnniversary?.id == second.id)
    }

    @Test("Annual leap-day anniversaries use February 28 in non-leap years")
    func leapDayAnniversaryUsesFebruary28() throws {
        var calendar = utcCalendar()
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let anniversary = anniversary(
            id: "leap-day",
            title: "闰日",
            date: "2024-02-29",
            annual: true
        )
        let reference = try #require(calendar.date(from: DateComponents(year: 2025, month: 1, day: 1)))
        let occurrence = try #require(anniversary.upcomingOccurrence(
            onOrAfter: reference,
            calendar: calendar
        ))
        let components = calendar.dateComponents([.year, .month, .day], from: occurrence)

        #expect(components.year == 2025)
        #expect(components.month == 2)
        #expect(components.day == 28)
    }

    @Test("Attachment flow clamps extreme image widths")
    func attachmentFlowClampsWidths() {
        #expect(AttachmentFlow.itemWidth(height: 144, aspectRatio: 0.01) == 82)
        #expect(AttachmentFlow.itemWidth(height: 144, aspectRatio: 1) == 144)
        #expect(AttachmentFlow.itemWidth(height: 144, aspectRatio: 20) == 216)
    }

    @Test("Deleting an unsent memory removes its mutation and staged photo")
    func deletingUnsentMemoryRemovesPendingAttachment() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let note = try await createMemoryWithPhoto(in: store)
        let record = try #require(store.pendingAttachmentRecords(for: note.id).first)
        try store.editMemory(
            id: note.id,
            content: "已编辑的带图动态",
            anniversaryId: nil,
            anniversaryTitle: nil,
            todoId: nil,
            todoTitle: nil,
            visibility: .shared
        )

        try await store.deleteMemory(id: note.id)

        #expect(try await store.loadSnapshot().notes.isEmpty)
        #expect(try await store.pendingOperations(limit: 100, now: .distantFuture).isEmpty)
        #expect(try store.pendingAttachmentRecords(for: note.id).isEmpty)
        await expectPendingFileMissing(store: store, relativePath: record.relativePath)
    }

    @Test("Failed attachment cleanup retains a retryable tombstone")
    func failedAttachmentCleanupRetainsRetryableTombstone() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let note = try await createMemoryWithPhoto(in: store)
        let record = try #require(store.pendingAttachmentRecords(for: note.id).first)
        let pendingDirectory = await store.attachmentFiles.pendingDirectory
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: pendingDirectory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pendingDirectory.path
            )
        }

        try await store.deleteMemory(id: note.id)

        var inspectionContext = ModelContext(store.container)
        var attachments = try inspectionContext.fetch(FetchDescriptor<LocalAttachmentEntity>())
        let retained = try #require(attachments.first { $0.id == record.localId })
        #expect(retained.isTombstoned)
        #expect(retained.localRelativePath == record.relativePath)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: pendingDirectory.path
        )
        _ = try await store.loadSnapshot()

        inspectionContext = ModelContext(store.container)
        attachments = try inspectionContext.fetch(FetchDescriptor<LocalAttachmentEntity>())
        #expect(attachments.allSatisfy { $0.id != record.localId })
        await expectPendingFileMissing(store: store, relativePath: record.relativePath)
    }

    @Test("Deleting a sending memory retains a server delete tombstone")
    func deletingSendingMemoryRetainsDeleteMutation() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let note = try await createMemoryWithPhoto(in: store)
        let record = try #require(store.pendingAttachmentRecords(for: note.id).first)
        let create = try #require(try await store.pendingOperations(
            limit: 100,
            now: .distantFuture
        ).first)
        try await store.markSending(operationIds: [create.operationId], now: .now)

        try await store.deleteMemory(id: note.id)

        let pending = try await store.pendingOperations(limit: 100, now: .distantFuture)
        #expect(pending.count == 1)
        #expect(pending.first?.mutationKind == .delete)
        #expect(pending.first?.entityId == note.id)
        #expect(try store.pendingAttachmentRecords(for: note.id).isEmpty)
        await expectPendingFileMissing(store: store, relativePath: record.relativePath)
    }

    @Test("Safe sign-out removes retained pending photo files")
    func safeSignOutRemovesRetainedPendingFiles() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let note = try await createMemoryWithPhoto(in: store)
        let record = try #require(store.pendingAttachmentRecords(for: note.id).first)
        let create = try #require(try await store.pendingOperations(
            limit: 100,
            now: .distantFuture
        ).first)
        try await store.acknowledge(operationIds: [create.operationId], now: .now)

        try await store.clearSynchronizedLocalDataForSignOut()

        #expect(try await store.loadSnapshot().notes.isEmpty)
        await expectPendingFileMissing(store: store, relativePath: record.relativePath)
    }

    private func makeStore() throws -> (OfflineStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ReviewFeedbackTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (try OfflineStore.makeInMemory(attachmentRoot: root), root)
    }

    private func createMemoryWithPhoto(in store: OfflineStore) async throws -> Note {
        try await store.createMemory(
            coupleId: "couple",
            ownerId: "owner",
            content: "带图动态",
            photos: [SelectedPhoto(
                data: Data([1, 2, 3]),
                filename: "photo.jpg",
                mimeType: "image/jpeg",
                width: 3,
                height: 2
            )],
            anniversaryId: nil,
            anniversaryTitle: nil,
            todoId: nil,
            todoTitle: nil,
            visibility: .shared
        )
    }

    private func expectPendingFileMissing(store: OfflineStore, relativePath: String) async {
        do {
            _ = try await store.pendingAttachment(relativePath: relativePath)
            Issue.record("Expected staged attachment file to be removed")
        } catch {
            // Expected: the staged file no longer exists.
        }
    }

    private func anniversary(
        id: String,
        title: String,
        daysFromNow: Int
    ) -> Anniversary {
        anniversary(
            id: id,
            title: title,
            date: Calendar.current.date(byAdding: .day, value: daysFromNow, to: .now)?.dateOnlyString ?? "",
            annual: false
        )
    }

    private func anniversary(
        id: String,
        title: String,
        date: String,
        annual: Bool
    ) -> Anniversary {
        Anniversary(
            id: id,
            coupleId: "couple",
            ownerId: "owner",
            title: title,
            date: date,
            annual: annual,
            visibility: .shared,
            reminderOffset: nil,
            reminderInstant: nil,
            createdAt: .now,
            updatedAt: .now,
            nextOccurrence: nil
        )
    }

    private func home(nextAnniversary: Anniversary?) -> HomeData {
        HomeData(
            daysTogether: 1,
            nextAnniversary: nextAnniversary,
            nextUpcoming: nil,
            latestTimelineEntry: nil
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
