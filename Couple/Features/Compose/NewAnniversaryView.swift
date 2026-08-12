import SwiftUI

struct NewAnniversaryView: View {
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date()
    @State private var annual = true
    @State private var visibility: Visibility = .shared
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("纪念日名称", text: $title) }
                Section {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                        .appHapticFeedback(.selection, trigger: date)
                    Toggle("每年纪念", isOn: $annual)
                        .appHapticFeedback(.selection, trigger: annual)
                }
                Section {
                    Picker("谁可以看", selection: $visibility) {
                        ForEach(Visibility.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .appHapticFeedback(.selection, trigger: visibility)
                }
            }
            .navigationTitle("新纪念日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark", action: cancel).labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark", action: beginSaving)
                        .labelStyle(.iconOnly)
                        .appProminentButtonStyle()
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .appHapticFeedback(
                .error,
                trigger: errorMessage,
                condition: AppHaptics.whenPresent
            )
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("好", role: .cancel, action: acknowledgeError) } message: { Text(errorMessage ?? "") }
        }
    }

    private func cancel() {
        haptics.play(.tap)
        dismiss()
    }

    private func beginSaving() {
        haptics.play(.tap)
        Task { await save() }
    }

    private func acknowledgeError() {
        haptics.play(.tap)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.addAnniversary(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                date: date,
                annual: annual,
                visibility: visibility
            )
            haptics.play(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
