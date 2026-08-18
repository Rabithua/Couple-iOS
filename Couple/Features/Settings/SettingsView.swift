import SwiftUI

struct SettingsView: View {
    @Environment(\.locale) private var locale
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppLanguageStore.self) private var language
    @Environment(AppStore.self) private var store
    let scrollingDisabled: Bool
    @State private var startedOn = Date.now
    @State private var persistedStartedOn: Date?
    @State private var hasLoadedDraftValues = false
    @State private var displayNameDraft = ""
    @State private var showingNameEditor = false
    @State private var showingNewAnniversary = false
    @State private var editingAnniversary: Anniversary?
    @State private var showingLeaveConfirmation = false
    @State private var showingUnsyncedLeave = false
    @State private var showingUnsyncedSignOut = false
    @State private var pendingChangeCount = 0
    @State private var isSavingName = false
    @State private var isPerformingAccountAction = false
    @State private var errorMessage = ""
    @State private var showingError = false

    var body: some View {
        @Bindable var haptics = haptics
        @Bindable var language = language

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                settingsSection("个人资料") {
                    Button(action: presentNameEditor) {
                        LabeledContent {
                            HStack(spacing: 6) {
                                Text(store.currentUser?.displayName ?? AppLocalization.string("未设置"))
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                        } label: {
                            Label("我的名字", systemImage: "person.crop.circle")
                        }
                    }
                    .settingsRow()
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("editDisplayNameButton")

                    ForEach(partnerMembers) { member in
                        LabeledContent {
                            Text(member.displayName)
                        } label: {
                            Label("另一半", systemImage: "heart")
                        }
                        .settingsRow()
                    }
                }

                settingsSection("共同空间") {
                    DatePicker("在一起的日期", selection: $startedOn, displayedComponents: .date)
                        .settingsRow()
                        .disabled(store.relationship?.couple == nil)
                        .accessibilityIdentifier("startedOnDatePicker")

                    if let invite = store.relationship?.pendingInvite {
                        LabeledContent("邀请码", value: invite.code)
                            .settingsRow()
                        ShareLink(item: AppLocalization.string(
                            "inviteShareMessage",
                            defaultValue: "加入我们的共同空间，邀请码：\(invite.code)"
                        )) {
                                Label("分享邀请码", systemImage: "square.and.arrow.up")
                            }
                            .settingsRow()
                    }
                }

                settingsSection("纪念日") {
                    ForEach(store.anniversaries) { item in
                        Label {
                            VStack(alignment: .leading) {
                                Text(item.title)
                                Text(anniversaryDate(item))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("anniversaryDate-\(item.id)")
                            }
                        } icon: {
                            Image(systemName: "birthday.cake.fill")
                        }
                        .settingsRow()
                        .editableContentActions(
                            deletionTitle: AppLocalization.string(
                                "deleteAnniversaryConfirmation",
                                defaultValue: "删除纪念日“\(item.title)”？"
                            ),
                            editAction: { editingAnniversary = item },
                            deleteAction: { try await store.deleteAnniversary(item) }
                        )
                    }

                    Button("添加纪念日", systemImage: "plus", action: presentNewAnniversary)
                        .settingsRow()
                        .buttonStyle(.plain)
                }

                settingsSection("偏好") {
                    Menu {
                        ForEach(AppLanguage.allCases) { option in
                            Button {
                                language.selection = option
                            } label: {
                                if option == language.selection {
                                    Label {
                                        Text(verbatim: option.displayName)
                                    } icon: {
                                        Image(systemName: "checkmark")
                                    }
                                } else {
                                    Text(verbatim: option.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Label("应用语言", systemImage: "globe")
                            Spacer()
                            Text(verbatim: language.selection.displayName)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .settingsRow()
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("appLanguagePicker")

                    Toggle(isOn: $haptics.isEnabled) {
                        Label(
                            "震动反馈",
                            systemImage: haptics.isEnabled ? "waveform" : "waveform.slash"
                        )
                    }
                    .settingsRow()
                    .accessibilityHint("控制应用内按钮、选择和操作结果的震动反馈")
                    .accessibilityIdentifier("hapticsToggle")
                }

                settingsSection("连接") {
                    LabeledContent("服务器", value: "oursince.com")
                        .settingsRow()
                    LabeledContent(
                        "登录",
                        value: store.isDemo ? AppLocalization.string("预览模式") : "Passkey"
                    )
                    .settingsRow()
                }

                settingsSection {
                    Button(role: .destructive) {
                        haptics.play(.warning)
                        showingLeaveConfirmation = true
                    } label: {
                        Label("退出空间", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(.red)
                    }
                    .settingsRow()
                    .buttonStyle(.plain)
                    .disabled(store.relationship?.couple == nil || isPerformingAccountAction)
                    .accessibilityIdentifier("leaveSpaceButton")
                    .confirmationDialog(
                        "退出当前共同空间？",
                        isPresented: $showingLeaveConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("确认退出空间", role: .destructive, action: beginLeavingSpace)
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text("退出后你将无法再查看这个空间；共同记录会为另一位成员保留。")
                    }

                    Button(role: .destructive) {
                        haptics.play(.warning)
                        beginSigningOut()
                    } label: {
                        Label("退出登录", systemImage: "person.crop.circle.badge.xmark")
                            .foregroundStyle(.red)
                    }
                    .settingsRow()
                    .buttonStyle(.plain)
                    .disabled(isPerformingAccountAction)
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.top, AppTheme.navigationBarHeight)
            .padding(.bottom, AppTheme.futureContentBottomPadding)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(scrollingDisabled)
        .accessibilityIdentifier("settingsForm")
        .overlay {
            if isSavingName || isPerformingAccountAction {
                ProgressView()
                    .controlSize(.large)
                    .padding(20)
                    .background(.regularMaterial, in: .rect(cornerRadius: 18))
            }
        }
        .task { loadDraftValues() }
        .task(id: startedOn.dateOnlyString) { await saveStartedOnIfNeeded() }
        .sheet(isPresented: $showingNewAnniversary) { NewAnniversaryView() }
        .sheet(item: $editingAnniversary) { anniversary in
            NewAnniversaryView(editing: anniversary)
        }
        .alert("修改名字", isPresented: $showingNameEditor) {
            TextField("你的名字", text: $displayNameDraft)
                .textInputAutocapitalization(.words)
            Button("保存", action: beginSavingName)
                .disabled(trimmedDisplayName.isEmpty || trimmedDisplayName.count > 100)
            Button("取消", role: .cancel) {}
        } message: {
            Text("对方会在共同空间里看到这个名字。")
        }
        .alert(AppLocalization.string("pendingChangeCountAlert",
            defaultValue: "还有 \(pendingChangeCount) 项尚未同步"
        ), isPresented: $showingUnsyncedLeave) {
            Button("先同步再退出", action: beginSyncThenLeave)
            Button("丢弃并退出", role: .destructive, action: beginDiscardingAndLeave)
            Button("取消", role: .cancel) {}
        } message: {
            Text("未同步的修改不会自动带出这个空间。")
        }
        .alert(AppLocalization.string("pendingChangeCountAlert",
            defaultValue: "还有 \(pendingChangeCount) 项尚未同步"
        ), isPresented: $showingUnsyncedSignOut) {
            Button("先同步", action: beginSyncThenSignOut)
            Button("丢弃并退出", role: .destructive, action: beginDiscardingAndSignOut)
            Button("取消", role: .cancel) {}
        } message: {
            Text("可以先同步后退出；只有选择丢弃，才会删除待同步操作和待上传照片。")
        }
        .alert("操作失败", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var partnerMembers: [CoupleMember] {
        guard let currentUserID = store.currentUser?.id else {
            return store.relationship?.members ?? []
        }
        return store.relationship?.members.filter { $0.id != currentUserID } ?? []
    }

    private var trimmedDisplayName: String {
        displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func anniversaryDate(_ anniversary: Anniversary) -> String {
        Date.fromDateOnly(anniversary.date)?.localizedDate(locale: locale) ?? anniversary.date
    }

    private func loadDraftValues() {
        displayNameDraft = store.currentUser?.displayName ?? ""
        defer { hasLoadedDraftValues = true }
        guard let rawDate = store.relationship?.couple?.startedOn,
              let date = Date.fromDateOnly(rawDate) else { return }
        persistedStartedOn = date
        startedOn = date
    }

    private func presentNameEditor() {
        displayNameDraft = store.currentUser?.displayName ?? ""
        haptics.play(.tap)
        showingNameEditor = true
    }

    private func beginSavingName() {
        guard !isSavingName, !trimmedDisplayName.isEmpty else { return }
        isSavingName = true
        haptics.play(.tap)
        Task { await saveDisplayName() }
    }

    private func presentNewAnniversary() {
        haptics.play(.tap)
        showingNewAnniversary = true
    }

    private func beginLeavingSpace() {
        switch store.signOutDisposition() {
        case .ready:
            performAccountAction(store.leaveSpaceIfSafe)
        case .requiresDecision(let count):
            pendingChangeCount = count
            showingUnsyncedLeave = true
        }
    }

    private func beginSyncThenLeave() {
        performAccountAction(store.syncThenLeaveSpace)
    }

    private func beginDiscardingAndLeave() {
        performAccountAction(store.discardChangesAndLeaveSpace)
    }

    private func beginSigningOut() {
        switch store.signOutDisposition() {
        case .ready:
            performAccountAction(store.signOutIfSafe)
        case .requiresDecision(let count):
            pendingChangeCount = count
            showingUnsyncedSignOut = true
        }
    }

    private func beginSyncThenSignOut() {
        performAccountAction(store.syncThenSignOut)
    }

    private func beginDiscardingAndSignOut() {
        performAccountAction(store.discardChangesAndSignOut)
    }

    private func performAccountAction(_ action: @escaping @MainActor () async -> Bool) {
        guard !isPerformingAccountAction else { return }
        isPerformingAccountAction = true
        Task {
            let succeeded = await action()
            isPerformingAccountAction = false
            if succeeded {
                haptics.play(.success)
            } else {
                presentError(
                    store.errorMessage ?? AppLocalization.string("操作未能完成，请稍后重试。")
                )
            }
        }
    }

    private func saveDisplayName() async {
        defer { isSavingName = false }
        do {
            try await store.updateDisplayName(trimmedDisplayName)
            haptics.play(.success)
        } catch {
            presentError(error.localizedDescription)
        }
    }

    private func saveStartedOnIfNeeded() async {
        guard hasLoadedDraftValues, store.relationship?.couple != nil else { return }
        let selectedDate = startedOn
        guard selectedDate.dateOnlyString != persistedStartedOn?.dateOnlyString else { return }

        do {
            try await Task.sleep(for: .milliseconds(350))
            try Task.checkCancellation()
            try await store.updateCouple(startedOn: selectedDate)
            try Task.checkCancellation()
            persistedStartedOn = selectedDate
            haptics.play(.success)
        } catch {
            guard !Task.isCancelled else { return }
            if let persistedStartedOn {
                startedOn = persistedStartedOn
            }
            presentError(error.localizedDescription)
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showingError = true
        haptics.play(.error)
    }
}

private extension View {
    func settingsRow() -> some View {
        frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
    }
}
