import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ComposeMemoryView: View {
    @Environment(AppHaptics.self) private var haptics
    @Environment(MemoryLocationCoordinator.self) private var memoryLocation
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let editingNote: Note?
    @State private var content: String
    @State private var visibility: Visibility
    @State private var anniversaryId: String?
    @State private var todoId: String?
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var photos: [SelectedPhoto] = []
    @State private var isSaving = false
    @State private var localError: String?

    init(editing note: Note? = nil) {
        editingNote = note
        _content = State(initialValue: note?.content ?? "")
        _visibility = State(initialValue: note?.visibility ?? .shared)
        _anniversaryId = State(initialValue: note?.anniversaryId)
        _todoId = State(initialValue: note?.todoId)
    }

    var body: some View {
        let photoCount = photos.count
        NavigationStack {
            Form {
                Section {
                    TextField("写下此刻……", text: $content, axis: .vertical)
                        .lineLimit(5...12)
                        .accessibilityIdentifier("memoryContentField")
                }

                Section("照片") {
                    if let editingNote {
                        if editingNote.attachments.isEmpty {
                            Text("没有照片")
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal) {
                                AttachmentFlow(attachments: editingNote.attachments, height: 88)
                            }
                            .scrollIndicators(.hidden)
                            Text("编辑会保留已有照片")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: 10,
                            matching: .images
                        ) {
                            Label(
                                photoCount == 0
                                    ? AppLocalization.string("选择照片")
                                    : AppLocalization.string("selectedPhotoCount",
                                        defaultValue: "已选择 \(photoCount) 张"
                                    ),
                                systemImage: "photo.on.rectangle.angled"
                            )
                        }
                        .appHapticFeedback(.selection, trigger: selectedItems)
                        .accessibilityIdentifier("memoryPhotoPicker")

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
                }

                Section {
                    MemoryLocationPicker(photoLocations: uniquePhotoLocations)
                }

                Section("关联") {
                    Picker("纪念日", selection: $anniversaryId) {
                        Text("不关联").tag(String?.none)
                        ForEach(store.anniversaries) { item in
                            Text(item.displayTitle).tag(String?.some(item.id))
                        }
                    }
                    .appHapticFeedback(.selection, trigger: anniversaryId)
                    .accessibilityIdentifier("memoryAnniversaryPicker")
                    Picker("共同清单", selection: $todoId) {
                        Text("不关联").tag(String?.none)
                        ForEach(store.todos) { item in
                            Text(item.title).tag(String?.some(item.id))
                        }
                    }
                    .appHapticFeedback(.selection, trigger: todoId)
                }

                Section {
                    Picker("谁可以看", selection: $visibility) {
                        ForEach(Visibility.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .appHapticFeedback(.selection, trigger: visibility)
                }
            }
            .navigationTitle(
                editingNote == nil
                    ? AppLocalization.string("记录此刻")
                    : AppLocalization.string("编辑动态")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark", action: cancel)
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark", action: beginSaving)
                        .labelStyle(.iconOnly)
                        .appProminentButtonStyle()
                        .disabled(!isValid || isSaving || memoryLocation.isCapturing)
                        .accessibilityIdentifier("saveMemoryButton")
                }
            }
            .overlay { if isSaving { ProgressView().controlSize(.large) } }
            .appHapticFeedback(
                .error,
                trigger: localError,
                condition: AppHaptics.whenPresent
            )
            .task(id: selectedItems) {
                do {
                    photos = try await load(selectedItems)
                } catch is CancellationError {
                    return
                } catch {
                    localError = error.localizedDescription
                }
            }
            .task(id: editingNote?.id) {
                memoryLocation.prepare(
                    existingLocation: editingNote?.location,
                    automaticallyCapture: shouldAutomaticallyCaptureLocation
                )
            }
            .onDisappear {
                memoryLocation.cancelPendingWork()
            }
            .alert("保存失败", isPresented: Binding(
                get: { localError != nil },
                set: { if !$0 { localError = nil } }
            )) {
                Button("好", role: .cancel, action: dismissError)
            } message: {
                Text(localError ?? "")
            }
        }
        .contentEditorSheetPresentation(detent: .large)
    }

    private var isValid: Bool {
        Note.hasRecordContent(
            text: content,
            attachmentCount: photos.count + (editingNote?.attachments.count ?? 0)
        )
    }

    private var shouldAutomaticallyCaptureLocation: Bool {
        guard editingNote == nil else { return false }
        let arguments = ProcessInfo.processInfo.arguments
        return !arguments.contains("-ui-testing-demo")
            || arguments.contains("-ui-testing-location")
    }

    private var availablePhotoLocations: [NoteLocation] {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-photo-locations") {
            return [
                NoteLocation(
                    latitude: 30.240_125,
                    longitude: 120.102_249,
                    name: "灵隐寺"
                ),
                NoteLocation(
                    latitude: 30.274_084_8,
                    longitude: 120.155_070_7,
                    name: "西湖"
                )
            ]
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-photo-location") {
            return [NoteLocation(
                latitude: 30.240_125,
                longitude: 120.102_249,
                name: "灵隐寺"
            )]
        }
#endif
        return photos.compactMap(\.location)
    }

    private var uniquePhotoLocations: [NoteLocation] {
        availablePhotoLocations.reduce(into: []) { uniqueLocations, location in
            guard !uniqueLocations.contains(where: { sameCoordinate($0, location) }) else {
                return
            }
            uniqueLocations.append(location)
        }
    }

    private func sameCoordinate(_ lhs: NoteLocation, _ rhs: NoteLocation) -> Bool {
        abs(lhs.latitude - rhs.latitude) < 0.000_001
            && abs(lhs.longitude - rhs.longitude) < 0.000_001
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

    private func dismissError() {
        haptics.play(.tap)
        localError = nil
    }

    private func load(_ items: [PhotosPickerItem]) async throws -> [SelectedPhoto] {
        var loaded: [SelectedPhoto] = []
        for item in items {
            try Task.checkCancellation()
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            let type = item.supportedContentTypes.first ?? .jpeg
            let location = PhotoLocationExtractor.location(
                itemIdentifier: item.itemIdentifier,
                imageData: data
            )
            loaded.append(
                SelectedPhoto(
                    data: data,
                    filename: "memory-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "jpg")",
                    mimeType: type.preferredMIMEType ?? "image/jpeg",
                    width: Int(image.size.width * image.scale),
                    height: Int(image.size.height * image.scale),
                    location: location
                )
            )
        }
        return loaded
    }

    private func save() async {
        defer { isSaving = false }
        do {
            let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if let editingNote {
                try await store.updateMemory(
                    editingNote,
                    content: cleanedContent,
                    anniversaryId: anniversaryId,
                    todoId: todoId,
                    location: memoryLocation.location,
                    visibility: visibility
                )
            } else {
                try await store.addMemory(
                    content: cleanedContent,
                    photos: photos,
                    anniversaryId: anniversaryId,
                    todoId: todoId,
                    location: memoryLocation.location,
                    visibility: visibility
                )
            }
            haptics.play(.success)
            dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }
}
