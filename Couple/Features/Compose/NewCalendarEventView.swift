import SwiftUI

struct NewCalendarEventView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let initialDate: Date
    @State private var title = ""
    @State private var start: Date
    @State private var end: Date
    @State private var allDay = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(initialDate: Date) {
        self.initialDate = initialDate
        _start = State(initialValue: initialDate)
        _end = State(initialValue: initialDate.addingTimeInterval(3_600))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("日程名称", text: $title) }
                Section {
                    Toggle("全天", isOn: $allDay)
                    DatePicker("开始", selection: $start, displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                    DatePicker("结束", selection: $end, in: start..., displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                }
            }
            .navigationTitle("新日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark") { Task { await save() } }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("好", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.addCalendarEvent(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                start: start,
                end: end,
                allDay: allDay
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

