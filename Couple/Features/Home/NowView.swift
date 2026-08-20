import SwiftUI

struct NowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(AppHaptics.self) private var haptics
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
        return names.isEmpty ? AppLocalization.string("你们") : names.joined(separator: " & ")
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

    private var needsPairing: Bool {
        guard let relationship = store.relationship else { return false }
        return relationship.members.count < 2
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: AppTheme.homeSectionSpacing) {
                    if needsPairing {
                        HomeInviteRow()
                        DesignDivider()
                    }
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
            .accessibilityIdentifier("nowScroll")

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
        let daysTogether = store.home?.daysTogether ?? 0

        return VStack(alignment: .leading, spacing: 4) {
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
                Text(daysTogether, format: .number)
                    .font(AppTheme.roundedNumberFont())
                    .contentTransition(.numericText())
                Text(dayUnit(for: daysTogether))
                    .font(AppTheme.titleFont())
            }

            if !featuredAttachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(alignment: .bottom, spacing: AppTheme.heroPhotoSpacing) {
                        ForEach(Array(featuredAttachments.enumerated()), id: \.element.id) { index, attachment in
                            let photoWidth = AttachmentFlow.itemWidth(
                                height: 120,
                                aspectRatio: attachment.aspectRatio
                            )
                            let note = store.notes.first { candidate in
                                candidate.attachments.contains { $0.id == attachment.id }
                            }

                            PhotoPreviewSource(
                                groupID: "home.featured",
                                attachments: featuredAttachments,
                                attachment: attachment,
                                transitionStyle: .featuredPhoto
                            ) {
                                AttachmentImage(
                                    attachment: attachment,
                                    contentMode: .fit,
                                    maximumDisplayDimension: max(photoWidth, 120)
                                )
                                    .frame(
                                        width: photoWidth,
                                        height: 120
                                    )
                                    .clipped()
                                    .overlay { Rectangle().stroke(Color.white, lineWidth: 3) }
                                    .shadow(color: .black.opacity(0.2), radius: 14, y: 4)
                                    .rotationEffect(.degrees(-1))
                            }
                                .accessibilityIdentifier("featuredPhoto-\(index)")
                                .editableContentActions(
                                    deletionTitle: AppLocalization.string("删除这条动态及其中照片？"),
                                    editAction: {
                                        if let note { editingNote = note }
                                    },
                                    deleteAction: {
                                        if let note { try await store.deleteMemory(note) }
                                    }
                                )
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
                .onDisappear {
                    setPhotoCarouselFrame(.zero)
                }
                .accessibilityIdentifier("featuredPhotoCarousel")
            }

            Text("每天都是独一无二纪念日，庆祝一下吧 🎉")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.horizontalPadding)
    }

    private var anniversarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let anniversary = nextAnniversary {
                let days = daysUntil(anniversary)
                HStack(spacing: 4) {
                    Text("下一个纪念日还有")
                        .font(AppTheme.titleFont())
                    Text(days, format: .number)
                        .font(AppTheme.roundedNumberFont())
                    Text(dayUnit(for: days))
                        .font(AppTheme.titleFont())
                }

                HStack(alignment: .top, spacing: 9) {
                    AssociationArrow(height: 45)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            (anniversary.upcomingOccurrence() ?? Date())
                                .localizedDateTime(locale: locale)
                        )
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                        Label(anniversary.title, systemImage: "birthday.cake.fill")
                            .font(AppTheme.titleFont())
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .editableContentActions(
                    deletionTitle: AppLocalization.string("deleteAnniversaryConfirmation",
                        defaultValue: "删除纪念日“\(anniversary.title)”？"
                    ),
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
                    disabled: store.pendingTodoIDs.contains(todo.id),
                    commitCompletion: {
                        await store.setTodoCompletion(todo, completed: true)
                    },
                    open: {
                        haptics.play(.tap)
                        editingTodo = todo
                    }
                )
                .editableContentActions(
                    deletionTitle: AppLocalization.string("deleteTodoConfirmation",
                        defaultValue: "删除清单“\(todo.title)”？"
                    ),
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

    private func daysUntil(_ anniversary: Anniversary) -> Int {
        guard let date = anniversary.upcomingOccurrence() else { return 0 }
        return max(
            Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: .now),
                to: date
            ).day ?? 0,
            0
        )
    }

    private func dayUnit(for count: Int) -> String {
        count == 1
            ? AppLocalization.string("dayUnitSingular", defaultValue: "天")
            : AppLocalization.string("dayUnitPlural", defaultValue: "天")
    }
}
