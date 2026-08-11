import SwiftUI

struct PastPageView: View {
    @Environment(AppStore.self) private var store
    let filter: PastFilter

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
        .contentMargins(.top, AppTheme.navigationBarHeight, for: .scrollContent)
        .refreshable { await store.selectNotes(filter.query, forceReload: true) }
        .accessibilityIdentifier(filter.scrollIdentifier)
    }

    private func timelineList(_ notes: [Note]) -> some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(notes) { note in
                if let association = note.associations.first {
                    AssociatedNoteRow(note: note, association: association)
                } else {
                    StandardNoteRow(note: note)
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
        let attachments = notes.flatMap(\.attachments).filter(\.isImage)
        return Group {
            if attachments.isEmpty {
                ContentUnavailableView("还没有照片", systemImage: "photo.on.rectangle.angled")
                    .padding(.top, 100)
            } else {
                AttachmentFlow(attachments: attachments)
            }
        }
    }

    private func completedList(_ notes: [Note]) -> some View {
        LazyVStack(alignment: .leading, spacing: 30) {
            ForEach(notes) { note in
                if let association = note.associations.first(where: { $0.type == .todo }) {
                    VStack(alignment: .leading, spacing: 8) {
                        NoteMetadataRow(date: note.createdAt, trailing: sampleLocation(for: note))
                        Label(association.title ?? "共同完成", systemImage: "checkmark.square")
                            .font(AppTheme.titleFont())
                    }
                }
            }
            if notes.allSatisfy({ $0.todoId == nil }) {
                ContentUnavailableView("还没有共同完成的事", systemImage: "checkmark.square")
                    .padding(.top, 100)
            }
        }
    }
}

private struct StandardNoteRow: View {
    let note: Note

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
                AttachmentFlow(attachments: note.attachments)
            }
        }
    }
}

private struct AssociatedNoteRow: View {
    let note: Note
    let association: NoteAssociation

    private var symbol: String {
        association.type == .anniversary ? "birthday.cake.fill" : "checkmark.square"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NoteMetadataRow(date: note.createdAt, trailing: sampleLocation(for: note))
            Label(association.title ?? "共同记录", systemImage: symbol)
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
                        AttachmentFlow(attachments: note.attachments)
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
            Text(date.chineseDateTime)
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
    return note.demoIndex == 0 ? "瓶窑镇良渚生长力聚落" : "虎山公园&杭钢公园"
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
