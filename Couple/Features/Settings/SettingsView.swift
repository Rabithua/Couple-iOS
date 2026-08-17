import SwiftUI

struct SettingsView: View {
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
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

        Form {
            Section("个人资料") {
                Button(action: presentNameEditor) {
                    LabeledContent {
                        HStack(spacing: 6) {
                            Text(store.currentUser?.displayName ?? "未设置")
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                    } label: {
                        Label("我的名字", systemImage: "person.crop.circle")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editDisplayNameButton")

                ForEach(partnerMembers) { member in
                    LabeledContent {
                        Text(member.displayName)
                    } label: {
                        Label("另一半", systemImage: "heart")
                    }
                }
            }
            .listRowSeparator(.hidden)

            Section("共同空间") {
                DatePicker("在一起的日期", selection: $startedOn, displayedComponents: .date)
                    .disabled(store.relationship?.couple == nil)
                    .accessibilityIdentifier("startedOnDatePicker")

                if let invite = store.relationship?.pendingInvite {
                    LabeledContent("邀请码", value: invite.code)
                    ShareLink(item: "加入我们的共同空间，邀请码：\(invite.code)") {
                        Label("分享邀请码", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .listRowSeparator(.hidden)

            Section {
                ForEach(store.anniversaries) { item in
                    Label {
                        VStack(alignment: .leading) {
                            Text(item.title)
                            Text(item.date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "birthday.cake.fill")
                    }
                    .editableContentActions(
                        deletionTitle: "删除纪念日“\(item.title)”？",
                        editAction: { editingAnniversary = item },
                        deleteAction: { try await store.deleteAnniversary(item) }
                    )
                }

                Button("添加纪念日", systemImage: "plus", action: presentNewAnniversary)
            } header: {
                Text("纪念日")
            }
            .listRowSeparator(.hidden)

            Section("偏好") {
                Toggle(isOn: $haptics.isEnabled) {
                    Label(
                        "震动反馈",
                        systemImage: haptics.isEnabled ? "waveform" : "waveform.slash"
                    )
                }
                .accessibilityHint("控制应用内按钮、选择和操作结果的震动反馈")
                .accessibilityIdentifier("hapticsToggle")
            }
            .listRowSeparator(.hidden)

            Section("连接") {
                LabeledContent("服务器", value: "oursince.com")
                LabeledContent("登录", value: store.isDemo ? "预览模式" : "Passkey")
            }
            .listRowSeparator(.hidden)

            Section {
                Button(role: .destructive) {
                    haptics.play(.warning)
                    showingLeaveConfirmation = true
                } label: {
                    Label("退出空间", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
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
                .disabled(isPerformingAccountAction)
            }
            .listRowSeparator(.hidden)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(
            .horizontal,
            0,
            for: .scrollContent
        )
        .contentMargins(.top, AppTheme.navigationBarHeight, for: .scrollContent)
        .contentMargins(
            .bottom,
            AppTheme.futureContentBottomPadding,
            for: .scrollContent
        )
        .scrollIndicators(.hidden)
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
        .alert("还有 \(pendingChangeCount) 项尚未同步", isPresented: $showingUnsyncedLeave) {
            Button("先同步再退出", action: beginSyncThenLeave)
            Button("丢弃并退出", role: .destructive, action: beginDiscardingAndLeave)
            Button("取消", role: .cancel) {}
        } message: {
            Text("未同步的修改不会自动带出这个空间。")
        }
        .alert("还有 \(pendingChangeCount) 项尚未同步", isPresented: $showingUnsyncedSignOut) {
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

    private var partnerMembers: [CoupleMember] {
        guard let currentUserID = store.currentUser?.id else {
            return store.relationship?.members ?? []
        }
        return store.relationship?.members.filter { $0.id != currentUserID } ?? []
    }

    private var trimmedDisplayName: String {
        displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
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
                presentError(store.errorMessage ?? "操作未能完成，请稍后重试。")
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
