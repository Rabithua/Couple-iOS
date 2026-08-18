import SwiftUI

struct PastPageView: View {
    @Environment(AppStore.self) private var store
    let filter: PastFilter
    let scrollingDisabled: Bool
    @State private var editingNote: Note?

    var body: some View {
        let notes = store.pastNotes(for: filter.query)

        ScrollView {
            Group {
                switch filter {
                case .all:
                    timelineList(notes)
                case .photos:
                    photoArchive(notes)
                case .anniversaries:
                    timelineList(notes)
                case .completed:
                    completedList(notes)
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(scrollingDisabled)
        .contentMargins(.top, AppTheme.navigationBarHeight, for: .scrollContent)
        .refreshable { await store.selectNotes(filter.query, forceReload: true) }
        .accessibilityIdentifier(filter.scrollIdentifier)
        .sheet(item: $editingNote) { note in
            ComposeMemoryView(editing: note)
        }
    }

    private func timelineList(_ notes: [Note]) -> some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(notes) { note in
                if let association = note.associations.first {
                    AssociatedNoteRow(
                        note: note,
                        association: association,
                        previewGroupID: previewGroupID(for: note)
                    )
                        .editableContentActions(
                            deletionTitle: AppLocalization.string("删除这条动态？"),
                            editAction: { editingNote = note },
                            deleteAction: { try await store.deleteMemory(note) }
                        )
                } else {
                    StandardNoteRow(
                        note: note,
                        previewGroupID: previewGroupID(for: note)
                    )
                        .editableContentActions(
                            deletionTitle: AppLocalization.string("删除这条动态？"),
                            editAction: { editingNote = note },
                            deleteAction: { try await store.deleteMemory(note) }
                        )
                }
            }
            if notes.isEmpty {
                ContentUnavailableView("还没有记录", systemImage: "heart.text.square")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
            }
        }
    }

    private func photoArchive(_ notes: [Note]) -> some View {
        let photoNotes = notes.filter { $0.attachments.contains(where: \.isImage) }
        return Group {
            if photoNotes.isEmpty {
                ContentUnavailableView("还没有照片", systemImage: "photo.on.rectangle.angled")
                    .padding(.top, 100)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(photoNotes) { note in
                        AttachmentFlow(
                            attachments: note.attachments.filter(\.isImage),
                            previewGroupID: previewGroupID(for: note)
                        )
                            .editableContentActions(
                                deletionTitle: AppLocalization.string("删除这条动态及其中照片？"),
                                editAction: { editingNote = note },
                                deleteAction: { try await store.deleteMemory(note) }
                            )
                    }
                }
            }
        }
    }

    private func completedList(_ notes: [Note]) -> some View {
        LazyVStack(alignment: .leading, spacing: 30) {
            ForEach(notes) { note in
                if let association = note.associations.first(where: { $0.type == .todo }) {
                    VStack(alignment: .leading, spacing: 8) {
                        NoteMetadataRow(date: note.createdAt, trailing: sampleLocation(for: note))
                        Label(
                            association.title ?? AppLocalization.string("共同完成"),
                            systemImage: "checkmark.square"
                        )
                            .font(AppTheme.titleFont())
                    }
                    .editableContentActions(
                        deletionTitle: AppLocalization.string("删除这条动态？"),
                        editAction: { editingNote = note },
                        deleteAction: { try await store.deleteMemory(note) }
                    )
                }
            }
            if notes.allSatisfy({ $0.todoId == nil }) {
                ContentUnavailableView("还没有共同完成的事", systemImage: "checkmark.square")
                    .padding(.top, 100)
            }
        }
    }

    private func previewGroupID(for note: Note) -> String {
        "past.\(filter.scrollIdentifier).\(note.id)"
    }
}

private struct StandardNoteRow: View {
    let note: Note
    let previewGroupID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NoteMetadataRow(date: note.createdAt, trailing: sampleLocation(for: note))
            if !note.content.isEmpty {
                Text(note.content)
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !note.attachments.isEmpty {
                AttachmentFlow(
                    attachments: note.attachments,
                    previewGroupID: previewGroupID
                )
            }
        }
    }
}

private struct AssociatedNoteRow: View {
    let note: Note
    let association: NoteAssociation
    let previewGroupID: String

    private var symbol: String {
        association.type == .anniversary ? "birthday.cake.fill" : "checkmark.square"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NoteMetadataRow(date: note.createdAt, trailing: sampleLocation(for: note))
            Label(association.title ?? AppLocalization.string("共同记录"), systemImage: symbol)
                .font(AppTheme.titleFont())

            HStack(alignment: .top, spacing: 10) {
                AssociationArrow(height: 122)
                    .padding(.leading, 8)
                VStack(alignment: .leading, spacing: 8) {
                    NoteMetadataRow(date: note.createdAt, trailing: "")
                    if !note.content.isEmpty {
                        Text(note.content)
                            .font(.title3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !note.attachments.isEmpty {
                        AttachmentFlow(
                            attachments: note.attachments,
                            previewGroupID: previewGroupID
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct NoteMetadataRow: View {
    let date: Date
    let trailing: String

    var body: some View {
        HStack {
            Text(date.localizedDateTime)
            Spacer(minLength: 8)
            Text(trailing)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(AppTheme.muted)
    }
}

private func sampleLocation(for note: Note) -> String {
    guard note.demoIndex < 2 else { return "" }
    return note.demoIndex == 0
        ? AppLocalization.string("瓶窑镇良渚生长力聚落")
        : AppLocalization.string("虎山公园&杭钢公园")
}

private extension Note {
    var demoIndex: Int {
        switch id {
        case "50000000-0000-4000-8000-000000000001": 0
        case "50000000-0000-4000-8000-000000000002": 1
        default: 99
        }
    }
}
