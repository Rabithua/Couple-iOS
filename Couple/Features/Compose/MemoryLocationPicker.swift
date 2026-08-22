import SwiftUI
import UIKit

struct MemoryLocationPicker: View {
    private enum ChoiceID {
        static let none = "none"
        static let current = "current"
        static let existing = "existing"
        static let status = "status"
        static let settings = "settings"
    }

    @Environment(AppHaptics.self) private var haptics
    @Environment(MemoryLocationCoordinator.self) private var memoryLocation
    @Environment(\.openURL) private var openURL
    @State private var resolvedPhotoLocations: [NoteLocation] = []
    @State private var selectedChoice = ChoiceID.none
    let photoLocations: [NoteLocation]

    var body: some View {
        Picker("位置", selection: $selectedChoice) {
            Text("不添加")
                .tag(ChoiceID.none)
                .accessibilityIdentifier("removeMemoryLocationButton")

            Text(currentLocationTitle)
                .tag(ChoiceID.current)
                .accessibilityIdentifier("useCurrentMemoryLocationButton")

            ForEach(presentedPhotoLocations.indices, id: \.self) { index in
                let location = presentedPhotoLocations[index]
                Text(photoLocationTitle(location, index: index))
                    .tag(photoChoiceID(location))
            }

            if let existingChoice {
                Text(existingChoice.1)
                    .tag(existingChoice.0)
            }

            if let statusChoice {
                Text(statusChoice.1)
                    .tag(statusChoice.0)
            }

            if shouldOfferSettings {
                Text("打开系统设置")
                    .tag(ChoiceID.settings)
                    .accessibilityIdentifier("openMemoryLocationSettingsButton")
            }
        }
        .accessibilityValue(valueTitle)
        .accessibilityIdentifier("memoryLocationPicker")
        .onChange(of: selectedChoice) { _, choice in
            guard choice != derivedChoice else { return }
            select(choice)
        }
        .onChange(of: derivedChoice) { _, choice in
            selectedChoice = choice
        }
        .onAppear {
            selectedChoice = derivedChoice
        }
        .task(id: photoLocations) {
            let resolvedLocations = await memoryLocation.resolvingPhotoLocationNames(
                photoLocations
            )
            guard !Task.isCancelled else { return }
            resolvedPhotoLocations = resolvedLocations
        }
    }

    private var derivedChoice: String {
        if let statusChoice {
            return statusChoice.0
        }
        if let location = memoryLocation.location {
            if let photoLocation = presentedPhotoLocations.first(where: {
                sameCoordinate($0, location)
            }) {
                return photoChoiceID(photoLocation)
            }
            if let currentLocation = memoryLocation.currentLocation,
               sameCoordinate(currentLocation, location) {
                return ChoiceID.current
            }
            return ChoiceID.existing
        }
        if memoryLocation.isCapturing {
            return ChoiceID.current
        }
        return ChoiceID.none
    }

    private var existingChoice: (String, String)? {
        guard let location = memoryLocation.location,
              memoryLocation.currentLocation.map({ !sameCoordinate($0, location) }) ?? true,
              !presentedPhotoLocations.contains(where: { sameCoordinate($0, location) }),
              let name = specificName(location)
        else { return nil }
        return (ChoiceID.existing, name)
    }

    private var statusChoice: (String, String)? {
        let title: String
        switch memoryLocation.status {
        case .denied, .servicesDisabled, .failed:
            title = valueTitle
        default:
            return nil
        }
        return (ChoiceID.status, title)
    }

    private var presentedPhotoLocations: [NoteLocation] {
        guard resolvedPhotoLocations.count == photoLocations.count,
              zip(resolvedPhotoLocations, photoLocations).allSatisfy({
                  sameCoordinate($0.0, $0.1)
              })
        else { return photoLocations }
        return resolvedPhotoLocations
    }

    private var currentLocationTitle: String {
        if let currentLocation = memoryLocation.currentLocation,
           let name = specificName(currentLocation) {
            return name
        }
        if memoryLocation.status == .resolvingName {
            return AppLocalization.string("正在解析位置")
        }
        if memoryLocation.isCapturing {
            return AppLocalization.string("正在获取位置")
        }
        return AppLocalization.string("获取当前位置")
    }

    private var valueTitle: String {
        switch memoryLocation.status {
        case .idle:
            memoryLocation.location.flatMap(specificName) ?? AppLocalization.string("不添加")
        case .requestingAuthorization:
            AppLocalization.string("等待定位授权")
        case .locating:
            AppLocalization.string("正在获取位置")
        case .resolvingName:
            AppLocalization.string("正在解析位置")
        case .located:
            memoryLocation.location.flatMap(specificName)
                ?? AppLocalization.string("位置信息不可用")
        case .denied:
            AppLocalization.string("定位权限未开启")
        case .servicesDisabled:
            AppLocalization.string("系统定位服务已关闭")
        case .failed:
            memoryLocation.errorMessage
                ?? AppLocalization.string("没有获取到可用的位置，请重试")
        }
    }

    private var shouldOfferSettings: Bool {
        memoryLocation.status == .denied || memoryLocation.status == .servicesDisabled
    }

    private func photoLocationTitle(_ location: NoteLocation, index: Int) -> String {
        if let name = specificName(location) { return name }
        let title = AppLocalization.string("照片位置")
        return photoLocations.count == 1 ? title : "\(title) \(index + 1)"
    }

    private func specificName(_ location: NoteLocation) -> String? {
        guard let name = location.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }
        return name
    }

    private func sameCoordinate(_ lhs: NoteLocation, _ rhs: NoteLocation) -> Bool {
        abs(lhs.latitude - rhs.latitude) < 0.000_001
            && abs(lhs.longitude - rhs.longitude) < 0.000_001
    }

    private func select(_ choice: String) {
        switch choice {
        case ChoiceID.none:
            haptics.play(.selection)
            memoryLocation.removeLocation()
        case ChoiceID.current:
            haptics.play(.selection)
            memoryLocation.useCurrentLocation()
        case ChoiceID.settings:
            openSystemSettings()
            selectedChoice = derivedChoice
        default:
            guard let location = presentedPhotoLocations.first(where: {
                photoChoiceID($0) == choice
            }) else { return }
            haptics.play(.selection)
            memoryLocation.usePhotoLocation(location)
        }
    }

    private func photoChoiceID(_ location: NoteLocation) -> String {
        "photo:\(location.latitude):\(location.longitude)"
    }

    private func openSystemSettings() {
        haptics.play(.tap)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
