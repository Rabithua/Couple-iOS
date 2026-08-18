import SwiftUI

struct NewAnniversaryView: View {
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let editingAnniversary: Anniversary?
    @State private var title: String
    @State private var date: Date
    @State private var annual: Bool
    @State private var visibility: Visibility
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(editing anniversary: Anniversary? = nil) {
        editingAnniversary = anniversary
        _title = State(initialValue: anniversary?.title ?? "")
        _date = State(initialValue: anniversary.flatMap { Date.fromDateOnly($0.date) } ?? .now)
        _annual = State(initialValue: anniversary?.annual ?? true)
        _visibility = State(initialValue: anniversary?.visibility ?? .shared)
    }

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
            .navigationTitle(
                editingAnniversary == nil
                    ? AppLocalization.string("新纪念日")
                    : AppLocalization.string("编辑纪念日")
            )
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
        guard !isSaving else { return }
        isSaving = true
        haptics.play(.tap)
        Task { await save() }
    }

    private func acknowledgeError() {
        haptics.play(.tap)
    }

    private func save() async {
        defer { isSaving = false }
        do {
            let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let editingAnniversary {
                try await store.updateAnniversary(
                    editingAnniversary,
                    title: cleanedTitle,
                    date: date,
                    annual: annual,
                    visibility: visibility
                )
            } else {
                try await store.addAnniversary(
                    title: cleanedTitle,
                    date: date,
                    annual: annual,
                    visibility: visibility
                )
            }
            haptics.play(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
