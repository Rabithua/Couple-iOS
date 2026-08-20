import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ComposeMemoryView: View {
    @Environment(AppHaptics.self) private var haptics
    @Environment(MemoryLocationCoordinator.self) private var memoryLocation
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
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

                Section("位置") {
                    locationSectionContent
                }

                Section("关联") {
                    Picker("纪念日", selection: $anniversaryId) {
                        Text("不关联").tag(String?.none)
                        ForEach(store.anniversaries) { item in
                            Text(item.displayTitle).tag(String?.some(item.id))
                        }
                    }
                    .appHapticFeedback(.selection, trigger: anniversaryId)
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

    @ViewBuilder
    private var locationSectionContent: some View {
        switch memoryLocation.status {
        case .idle:
            locationActionButton(
                "添加当前位置",
                systemImage: "location",
                accessibilityIdentifier: "addMemoryLocationButton",
                action: requestLocation
            )
        case .requestingAuthorization:
            locationProgressRow("等待定位授权")
        case .locating:
            locationProgressRow("正在获取位置")
        case .located:
            if let location = memoryLocation.location {
                Label(location.displayName, systemImage: "mappin.and.ellipse")
                    .lineLimit(2)
                    .accessibilityIdentifier("memoryLocationValue")
                locationActionButton(
                    "移除位置",
                    systemImage: "location.slash",
                    role: .destructive,
                    accessibilityIdentifier: "removeMemoryLocationButton",
                    action: removeLocation
                )
            } else {
                refreshLocationButton
            }
        case .denied:
            Label("定位权限未开启", systemImage: "location.slash")
                .foregroundStyle(.secondary)
            openLocationSettingsButton
        case .servicesDisabled:
            Label("系统定位服务已关闭", systemImage: "location.slash")
                .foregroundStyle(.secondary)
            openLocationSettingsButton
        case .failed:
            Label(
                memoryLocation.errorMessage
                    ?? AppLocalization.string("没有获取到可用的位置，请重试"),
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.secondary)
            refreshLocationButton
        }
    }

    private var refreshLocationButton: some View {
        locationActionButton(
            "重新获取位置",
            systemImage: "location",
            accessibilityIdentifier: "refreshMemoryLocationButton",
            action: requestLocation
        )
    }

    private var openLocationSettingsButton: some View {
        locationActionButton(
            "打开系统设置",
            systemImage: "gear",
            accessibilityIdentifier: "openMemoryLocationSettingsButton",
            action: openSystemSettings
        )
    }

    private func locationActionButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        role: ButtonRole? = nil,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func locationProgressRow(_ title: LocalizedStringKey) -> some View {
        HStack {
            Label(title, systemImage: "location")
            Spacer()
            ProgressView()
        }
        .accessibilityElement(children: .combine)
    }

    private func requestLocation() {
        haptics.play(.tap)
        memoryLocation.captureCurrentLocation()
    }

    private func removeLocation() {
        haptics.play(.tap)
        memoryLocation.removeLocation()
    }

    private func openSystemSettings() {
        haptics.play(.tap)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
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
