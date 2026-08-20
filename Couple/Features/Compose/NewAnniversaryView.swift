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
    @State private var reminder: ReminderPreset
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(initialDate: Date = .now) {
        editingAnniversary = nil
        _title = State(initialValue: "")
        _date = State(initialValue: initialDate)
        _annual = State(initialValue: true)
        _visibility = State(initialValue: .shared)
        _reminder = State(initialValue: .oneDay)
    }

    init(editing anniversary: Anniversary) {
        editingAnniversary = anniversary
        _title = State(initialValue: anniversary.title)
        _date = State(initialValue: Date.fromDateOnly(anniversary.date) ?? .now)
        _annual = State(initialValue: anniversary.annual)
        _visibility = State(initialValue: anniversary.visibility)
        _reminder = State(initialValue: ReminderPreset.selected(
            enabled: anniversary.reminderEnabled,
            offset: anniversary.reminderOffset,
            default: .oneDay
        ))
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
                    Picker("提醒", selection: $reminder) {
                        ForEach(ReminderPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .appHapticFeedback(.selection, trigger: reminder)
                    if reminder.isEnabled {
                        LabeledContent("提醒时间", value: "09:00")
                    }
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
        .contentEditorSheetPresentation()
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
                    visibility: visibility,
                    reminder: reminder
                )
            } else {
                try await store.addAnniversary(
                    title: cleanedTitle,
                    date: date,
                    annual: annual,
                    visibility: visibility,
                    reminder: reminder
                )
            }
            haptics.play(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
