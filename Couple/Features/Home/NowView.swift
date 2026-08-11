import SwiftUI

struct NowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppStore.self) private var store
    @GestureState private var photoCarouselGestureActive = false
    let composePullProgress: CGFloat
    let showComposer: () -> Void
    let showSettings: () -> Void
    let setPhotoCarouselGestureActive: (Bool) -> Void

    private var memberNames: String {
        let names = store.relationship?.members.map(\.displayName) ?? []
        return names.isEmpty ? "你们" : names.joined(separator: " & ")
    }

    private var featuredAttachments: [Attachment] {
        Array(store.notes.flatMap(\.attachments).prefix(4))
    }

    private var activeTodos: [Todo] {
        store.todos.incompleteTodosOrderedByDueTime(limit: 4)
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
            .refreshable { await store.refreshContent() }

            pullToCompose
        }
        .overlay(alignment: .top) {
            DesignTopEdgeBackground(length: AppTheme.homeTopFadeLength)
        }
        .screenBackground()
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
                        AttachmentImage(attachment: attachment)
                            .frame(width: heroWidth(for: index), height: 120)
                            .overlay { Rectangle().stroke(Color.white, lineWidth: 3) }
                            .shadow(color: .black.opacity(0.2), radius: 14, y: 4)
                            .rotationEffect(.degrees(-1))
                            .accessibilityIdentifier("featuredPhoto-\(index)")
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
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .updating($photoCarouselGestureActive) { _, active, _ in active = true }
            )
            .onChange(of: photoCarouselGestureActive) { _, active in
                setPhotoCarouselGestureActive(active)
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
            if let anniversary = store.home?.nextAnniversary ?? store.anniversaries.first {
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
                        Text((Date.fromDateOnly(anniversary.nextOccurrence ?? anniversary.date) ?? Date()).chineseDateTime)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                        Label(anniversary.title, systemImage: "birthday.cake.fill")
                            .font(AppTheme.titleFont())
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        Button(action: showComposer) {
            VStack(spacing: 4) {
                Text(composePullProgress >= 1 ? "松开记录此刻" : "上拉记录此刻")
                    .font(.body)
                Image(systemName: "chevron.up.2")
                    .font(.body)
            }
            .foregroundStyle(AppTheme.muted)
            .frame(width: 120, height: 64)
            .contentShape(Rectangle())
            .offset(y: reduceMotion ? 0 : -composePullProgress * 10)
            .opacity(0.65 + composePullProgress * 0.35)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.14), value: composePullProgress >= 1)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
        .accessibilityLabel("记录此刻")
        .accessibilityHint("轻点或从页面底部上拉")
        .accessibilityIdentifier("composeMemoryButton")
    }

    private func heroWidth(for index: Int) -> CGFloat {
        [80, 180, 90, 80][index % 4]
    }

    private func daysUntil(_ anniversary: Anniversary) -> Int {
        guard let date = Date.fromDateOnly(anniversary.nextOccurrence ?? anniversary.date) else { return 0 }
        return max(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: date).day ?? 0, 0)
    }
}
