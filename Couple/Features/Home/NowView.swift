import SwiftUI

struct NowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppStore.self) private var store
    let composePullProgress: CGFloat
    let isActive: Bool
    let verticalScrollingDisabled: Bool
    let showComposer: () -> Void
    let showSettings: () -> Void
    let setPhotoCarouselFrame: (CGRect) -> Void
    @State private var editingNote: Note?
    @State private var editingTodo: Todo?
    @State private var editingAnniversary: Anniversary?

    private var memberNames: String {
        let names = store.relationship?.members.map(\.displayName) ?? []
        return names.isEmpty ? "你们" : names.joined(separator: " & ")
    }

    private var featuredAttachments: [Attachment] {
        Array(store.notes.flatMap(\.attachments).filter(\.isImage).prefix(4))
    }

    private var activeTodos: [Todo] {
        store.todos.incompleteTodosOrderedByDueTime(limit: 4)
    }

    private var nextAnniversary: Anniversary? {
        store.homeAnniversary
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 16) {
                    relationshipHero
                    DesignDivider()
                    anniversarySection
                    DesignDivider()
                    todoSection
                    Color.clear.frame(height: 70)
                }
                .padding(.top, AppTheme.topPadding)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(verticalScrollingDisabled)
            .refreshable { await store.refreshContent() }

            pullToCompose
        }
        .overlay(alignment: .top) {
            DesignTopEdgeBackground(length: AppTheme.homeTopFadeLength)
        }
        .screenBackground()
        .sheet(item: $editingNote) { note in
            ComposeMemoryView(editing: note)
        }
        .sheet(item: $editingTodo) { todo in
            NewTodoView(editing: todo)
        }
        .sheet(item: $editingAnniversary) { anniversary in
            NewAnniversaryView(editing: anniversary)
        }
    }

    private var relationshipHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: showSettings) {
                Text(memberNames)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开设置")

            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.title2.bold())
                Text("在一起")
                    .font(AppTheme.titleFont())
                Text("\(store.home?.daysTogether ?? 0)")
                    .font(AppTheme.roundedNumberFont())
                    .contentTransition(.numericText())
                Text("天")
                    .font(AppTheme.titleFont())
            }

            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: AppTheme.heroPhotoSpacing) {
                    ForEach(Array(featuredAttachments.enumerated()), id: \.element.id) { index, attachment in
                        let note = store.notes.first { candidate in
                            candidate.attachments.contains { $0.id == attachment.id }
                        }

                        PhotoPreviewSource(
                            groupID: "home.featured",
                            attachments: featuredAttachments,
                            attachment: attachment,
                            transitionStyle: .featuredPhoto
                        ) {
                            AttachmentImage(attachment: attachment, contentMode: .fit)
                                .frame(
                                    width: AttachmentFlow.itemWidth(
                                        height: 120,
                                        aspectRatio: attachment.aspectRatio
                                    ),
                                    height: 120
                                )
                                .clipped()
                                .overlay { Rectangle().stroke(Color.white, lineWidth: 3) }
                                .shadow(color: .black.opacity(0.2), radius: 14, y: 4)
                                .rotationEffect(.degrees(-1))
                        }
                            .accessibilityIdentifier("featuredPhoto-\(index)")
                            .editableContentActions(
                                deletionTitle: "删除这条动态及其中照片？",
                                editAction: {
                                    if let note { editingNote = note }
                                },
                                deleteAction: {
                                    if let note { try await store.deleteMemory(note) }
                                }
                            )
                    }
                    if featuredAttachments.isEmpty {
                        ForEach(0..<4, id: \.self) { index in
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(width: heroWidth(for: index), height: 120)
                                .overlay { Rectangle().stroke(Color.white, lineWidth: 3) }
                                .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
                                .rotationEffect(.degrees(-1))
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .contentMargins(.horizontal, AppTheme.heroPhotoScrollMargin, for: .scrollContent)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("mainPager"))
            } action: { frame in
                setPhotoCarouselFrame(frame)
            }
            .accessibilityIdentifier("featuredPhotoCarousel")

            Text("每天都是独一无二纪念日，庆祝一下吧 🎉")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
    }

    private var anniversarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let anniversary = nextAnniversary {
                let days = daysUntil(anniversary)
                HStack(spacing: 4) {
                    Text("下一个纪念日还有")
                        .font(AppTheme.titleFont())
                    Text("\(days)")
                        .font(AppTheme.roundedNumberFont())
                    Text("天")
                        .font(AppTheme.titleFont())
                }

                HStack(alignment: .top, spacing: 9) {
                    AssociationArrow(height: 45)
                    VStack(alignment: .leading, spacing: 4) {
                        Text((anniversary.upcomingOccurrence() ?? Date()).chineseDateTime)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                        Label(anniversary.title, systemImage: "birthday.cake.fill")
                            .font(AppTheme.titleFont())
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .editableContentActions(
                    deletionTitle: "删除纪念日“\(anniversary.title)”？",
                    editAction: { editingAnniversary = anniversary },
                    deleteAction: { try await store.deleteAnniversary(anniversary) }
                )
            } else {
                Text("还没有纪念日")
                    .font(AppTheme.titleFont())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.horizontalPadding)
    }

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.todoRowSpacing) {
            ForEach(activeTodos) { todo in
                DeferredTodoCompletionRow(
                    todo: todo,
                    disabled: store.pendingTodoIDs.contains(todo.id)
                ) {
                    await store.setTodoCompletion(todo, completed: true)
                }
                .editableContentActions(
                    deletionTitle: "删除清单“\(todo.title)”？",
                    editAction: { editingTodo = todo },
                    deleteAction: { try await store.deleteTodo(todo) }
                )
            }
            if activeTodos.isEmpty {
                Label("共同清单已经完成", systemImage: "checkmark.square")
                    .font(AppTheme.titleFont())
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: activeTodos.map(\.id))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.horizontalPadding)
    }

    private var pullToCompose: some View {
        ComposePullPrompt(
            progress: composePullProgress,
            isActive: isActive,
            action: showComposer
        )
    }

    private func heroWidth(for index: Int) -> CGFloat {
        [80, 180, 90, 80][index % 4]
    }

    private func daysUntil(_ anniversary: Anniversary) -> Int {
        guard let date = anniversary.upcomingOccurrence() else { return 0 }
        return max(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: date).day ?? 0, 0)
    }
}
