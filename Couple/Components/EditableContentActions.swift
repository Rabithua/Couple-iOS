import SwiftUI

struct EditableContentActionsModifier: ViewModifier {
    @Environment(AppHaptics.self) private var haptics
    let deletionTitle: String
    let editAction: @MainActor () -> Void
    let deleteAction: @MainActor () async throws -> Void

    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var isShowingDeleteError = false
    @State private var deleteErrorMessage = ""

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("编辑", systemImage: "pencil", action: beginEditing)
                Button(role: .destructive, action: requestDeletion) {
                    Label("删除", systemImage: "trash")
                }
                .disabled(isDeleting)
            }
            .confirmationDialog(
                deletionTitle,
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive, action: beginDeleting)
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后会从双方设备同步移除。")
            }
            .alert("删除失败", isPresented: $isShowingDeleteError) {
            } message: {
                Text(deleteErrorMessage)
            }
            .accessibilityAction(named: Text(AppLocalization.string("编辑")), beginEditing)
            .accessibilityAction(named: Text(AppLocalization.string("删除")), requestDeletion)
    }

    private func beginEditing() {
        haptics.play(.tap)
        editAction()
    }

    private func requestDeletion() {
        guard !isDeleting else { return }
        haptics.play(.warning)
        isShowingDeleteConfirmation = true
    }

    private func beginDeleting() {
        guard !isDeleting else { return }
        isDeleting = true
        Task { await deleteContent() }
    }

    private func deleteContent() async {
        defer { isDeleting = false }
        do {
            try await deleteAction()
            haptics.play(.success)
        } catch {
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            deleteErrorMessage = message.isEmpty
                ? AppLocalization.string("操作失败，请稍后重试")
                : message
            isShowingDeleteError = true
            haptics.play(.error)
        }
    }
}

extension View {
    func editableContentActions(
        deletionTitle: String,
        editAction: @escaping @MainActor () -> Void,
        deleteAction: @escaping @MainActor () async throws -> Void
    ) -> some View {
        modifier(EditableContentActionsModifier(
            deletionTitle: deletionTitle,
            editAction: editAction,
            deleteAction: deleteAction
        ))
    }
}
