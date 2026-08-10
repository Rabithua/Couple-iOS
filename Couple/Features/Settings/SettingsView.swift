import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var startedOn = Date()
    @State private var showingNewAnniversary = false
    @State private var isSaving = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("共同空间") {
                    ForEach(store.relationship?.members ?? []) { member in
                        Label(member.displayName, systemImage: "person.crop.circle")
                    }
                    DatePicker("在一起的日期", selection: $startedOn, displayedComponents: .date)
                    Button("保存日期") { Task { await saveDate() } }
                        .disabled(isSaving || store.isDemo)
                }

                if let invite = store.relationship?.pendingInvite {
                    Section("等待对方加入") {
                        LabeledContent("邀请码", value: invite.code)
                        ShareLink(item: "加入我的情侣共同空间，邀请码：\(invite.code)") {
                            Label("分享邀请码", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section {
                    ForEach(store.anniversaries) { item in
                        Label {
                            VStack(alignment: .leading) {
                                Text(item.title)
                                Text(item.date).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "birthday.cake.fill")
                        }
                    }
                    Button("添加纪念日", systemImage: "plus") { showingNewAnniversary = true }
                } header: {
                    Text("纪念日")
                }

                Section("连接") {
                    LabeledContent("服务器", value: "couple-server.rote.ink")
                    LabeledContent("登录", value: store.isDemo ? "预览模式" : "Passkey")
                }

                Section {
                    Button("退出登录", role: .destructive) {
                        Task {
                            await store.signOut()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task { loadStartedOn() }
            .sheet(isPresented: $showingNewAnniversary) { NewAnniversaryView() }
            .alert("保存失败", isPresented: Binding(
                get: { localError != nil },
                set: { if !$0 { localError = nil } }
            )) { Button("好", role: .cancel) {} } message: { Text(localError ?? "") }
        }
    }

    private func loadStartedOn() {
        if let raw = store.relationship?.couple?.startedOn,
           let date = Date.fromDateOnly(raw) {
            startedOn = date
        }
    }

    private func saveDate() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.updateCouple(startedOn: startedOn)
        } catch {
            localError = error.localizedDescription
        }
    }
}
