import SwiftUI

struct NewCalendarEventView: View {
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let initialDate: Date
    private let editingEvent: CalendarEvent?
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var allDay: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(initialDate: Date) {
        self.initialDate = initialDate
        editingEvent = nil
        _title = State(initialValue: "")
        _start = State(initialValue: initialDate)
        _end = State(initialValue: initialDate.addingTimeInterval(3_600))
        _allDay = State(initialValue: false)
    }

    init(editing event: CalendarEvent) {
        initialDate = event.startTime
        editingEvent = event
        _title = State(initialValue: event.title)
        _start = State(initialValue: event.startTime)
        _end = State(initialValue: event.endTime ?? event.startTime.addingTimeInterval(3_600))
        _allDay = State(initialValue: event.allDay)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("日程名称", text: $title) }
                Section {
                    Toggle("全天", isOn: $allDay)
                        .appHapticFeedback(.selection, trigger: allDay)
                    DatePicker("开始", selection: $start, displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                        .appHapticFeedback(.selection, trigger: start)
                    DatePicker("结束", selection: $end, in: start..., displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                        .appHapticFeedback(.selection, trigger: end)
                }
            }
            .navigationTitle(editingEvent == nil ? "新日程" : "编辑日程")
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
            if let editingEvent {
                try await store.updateCalendarEvent(
                    editingEvent,
                    title: cleanedTitle,
                    start: start,
                    end: end,
                    allDay: allDay
                )
            } else {
                try await store.addCalendarEvent(
                    title: cleanedTitle,
                    start: start,
                    end: end,
                    allDay: allDay
                )
            }
            haptics.play(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
