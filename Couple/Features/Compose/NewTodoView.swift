import SwiftUI

struct NewTodoView: View {
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let editingTodo: Todo?
    @State private var title: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var visibility: Visibility
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(editing todo: Todo? = nil) {
        editingTodo = todo
        _title = State(initialValue: todo?.title ?? "")
        _hasDueDate = State(initialValue: todo?.dueTime != nil)
        _dueDate = State(initialValue: todo?.dueTime ?? Date.now.addingTimeInterval(86_400))
        _visibility = State(initialValue: todo?.visibility ?? .shared)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("想一起做什么？") {
                    TextField("例如：去灵隐寺还愿", text: $title)
                }
                Section {
                    Toggle("设置日期", isOn: $hasDueDate)
                        .appHapticFeedback(.selection, trigger: hasDueDate)
                    if hasDueDate {
                        DatePicker("时间", selection: $dueDate)
                            .appHapticFeedback(.selection, trigger: dueDate)
                    }
                }
                Section {
                    Picker("谁可以看", selection: $visibility) {
                        ForEach(Visibility.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .appHapticFeedback(.selection, trigger: visibility)
                }
            }
            .navigationTitle(editingTodo == nil ? "新清单" : "编辑清单")
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
            if let editingTodo {
                try await store.updateTodo(
                    editingTodo,
                    title: cleanedTitle,
                    dueDate: hasDueDate ? dueDate : nil,
                    visibility: visibility
                )
            } else {
                try await store.addTodo(
                    title: cleanedTitle,
                    dueDate: hasDueDate ? dueDate : nil,
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
