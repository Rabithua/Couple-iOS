import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ComposeMemoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var visibility: Visibility = .shared
    @State private var anniversaryId: String?
    @State private var todoId: String?
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var photos: [SelectedPhoto] = []
    @State private var isSaving = false
    @State private var localError: String?

    var body: some View {
        let photoCount = photos.count
        NavigationStack {
            Form {
                Section {
                    TextField("写下此刻……", text: $content, axis: .vertical)
                        .lineLimit(5...12)
                }

                Section("照片") {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 10,
                        matching: .images
                    ) {
                        Label(photoCount == 0 ? "选择照片" : "已选择 \(photoCount) 张", systemImage: "photo.on.rectangle.angled")
                    }

                    if !photos.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(photos) { photo in
                                    if let image = UIImage(data: photo.data) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 88, height: 88)
                                            .clipShape(.rect(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                Section("关联") {
                    Picker("纪念日", selection: $anniversaryId) {
                        Text("不关联").tag(String?.none)
                        ForEach(store.anniversaries) { item in
                            Text(item.title).tag(String?.some(item.id))
                        }
                    }
                    Picker("共同清单", selection: $todoId) {
                        Text("不关联").tag(String?.none)
                        ForEach(store.todos) { item in
                            Text(item.title).tag(String?.some(item.id))
                        }
                    }
                }

                Section {
                    Picker("谁可以看", selection: $visibility) {
                        ForEach(Visibility.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }
            }
            .navigationTitle("记录此刻")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark") {
                        Task { await save() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid || isSaving)
                    .accessibilityIdentifier("saveMemoryButton")
                }
            }
            .overlay { if isSaving { ProgressView().controlSize(.large) } }
            .task(id: selectedItems) {
                do {
                    photos = try await load(selectedItems)
                } catch is CancellationError {
                    return
                } catch {
                    localError = error.localizedDescription
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { localError != nil },
                set: { if !$0 { localError = nil } }
            )) {
                Button("好", role: .cancel) { localError = nil }
            } message: {
                Text(localError ?? "")
            }
        }
    }

    private var isValid: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty
    }

    private func load(_ items: [PhotosPickerItem]) async throws -> [SelectedPhoto] {
        var loaded: [SelectedPhoto] = []
        for item in items {
            try Task.checkCancellation()
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            let type = item.supportedContentTypes.first ?? .jpeg
            loaded.append(
                SelectedPhoto(
                    data: data,
                    filename: "memory-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "jpg")",
                    mimeType: type.preferredMIMEType ?? "image/jpeg",
                    width: Int(image.size.width * image.scale),
                    height: Int(image.size.height * image.scale)
                )
            )
        }
        return loaded
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.addMemory(
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                photos: photos,
                anniversaryId: anniversaryId,
                todoId: todoId,
                visibility: visibility
            )
            dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }
}
