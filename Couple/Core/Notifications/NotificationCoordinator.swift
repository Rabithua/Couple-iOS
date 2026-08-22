import Observation
import SwiftUI
import UserNotifications

enum NotificationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized: self = .authorized
        case .provisional: self = .provisional
        case .ephemeral: self = .ephemeral
        @unknown default: self = .denied
        }
    }

    var allowsNotifications: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: true
        case .notDetermined, .denied: false
        }
    }

    var title: String {
        switch self {
        case .notDetermined: AppLocalization.string("未请求")
        case .denied: AppLocalization.string("已关闭")
        case .authorized: AppLocalization.string("已允许")
        case .provisional: AppLocalization.string("临时允许")
        case .ephemeral: AppLocalization.string("暂时允许")
        }
    }
}

@MainActor
@Observable
final class NotificationCoordinator {
    static let shared = NotificationCoordinator()
    static let collaborationDefaultsKey = "app.notifications.collaboration"
    static let remindersDefaultsKey = "app.notifications.reminders"

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private weak var store: AppStore?
    private weak var language: AppLanguageStore?
    private var deviceToken: String?
    private var isUploading = false

    private(set) var authorizationStatus: NotificationAuthorizationStatus = .notDetermined
    private(set) var registrationError: String?
    var pendingDestination: NotificationDestination?
    var collaborationEnabled: Bool {
        didSet {
            defaults.set(collaborationEnabled, forKey: Self.collaborationDefaultsKey)
            Task { await updatePreferences() }
        }
    }
    var remindersEnabled: Bool {
        didSet {
            defaults.set(remindersEnabled, forKey: Self.remindersDefaultsKey)
            Task { await updatePreferences() }
        }
    }

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.defaults = defaults
        collaborationEnabled = defaults.object(forKey: Self.collaborationDefaultsKey) as? Bool ?? true
        remindersEnabled = defaults.object(forKey: Self.remindersDefaultsKey) as? Bool ?? true
    }

    func configure(store: AppStore, language: AppLanguageStore) async {
        self.store = store
        self.language = language
        await refreshAuthorizationStatus()
        guard store.shouldRegisterPushDevice else { return }
        UIApplication.shared.registerForRemoteNotifications()
        await uploadRegistrationIfPossible()
    }

    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        guard let store, store.shouldRegisterPushDevice else { return false }
        await refreshAuthorizationStatus()
        if authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                registrationError = error.localizedDescription
            }
            await refreshAuthorizationStatus()
        }
        UIApplication.shared.registerForRemoteNotifications()
        return authorizationStatus.allowsNotifications
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = NotificationAuthorizationStatus(
            await center.notificationSettings().authorizationStatus
        )
    }

    func receiveDeviceToken(_ data: Data) async {
        deviceToken = data.map {
            let hex = String($0, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
        registrationError = nil
        await uploadRegistrationIfPossible()
    }

    func receiveRegistrationError(_ error: Error) {
        registrationError = error.localizedDescription
    }

    func refreshRegistration() async {
        await refreshAuthorizationStatus()
        if let store,
           store.shouldRegisterPushDevice {
            UIApplication.shared.registerForRemoteNotifications()
            await uploadRegistrationIfPossible()
        }
    }

    func unregisterCurrentDevice() async throws {
        guard let store,
              !store.isDemo,
              let deviceId = store.notificationDeviceIdentifier()
        else {
            UIApplication.shared.unregisterForRemoteNotifications()
            deviceToken = nil
            return
        }
        do {
            try await store.api.deletePushDevice(deviceId: deviceId)
        } catch {
            registrationError = error.localizedDescription
            throw error
        }
        unregisterLocalDevice()
        registrationError = nil
    }

    func unregisterLocalDevice() {
        UIApplication.shared.unregisterForRemoteNotifications()
        deviceToken = nil
    }

    func handleForegroundNotification(_ userInfo: [AnyHashable: Any]) async {
        guard let store, !store.isDemo else { return }
        _ = await store.synchronizeFromPush()
        if let destination = NotificationDestination(userInfo: userInfo),
           destination.eventType == "pair_accepted" {
            await store.refreshRelationshipFromPush()
        }
    }

    func handleBackgroundNotification(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard let store, !store.isDemo else { return .noData }
        let result = await store.synchronizeFromPush()
        if let destination = NotificationDestination(userInfo: userInfo),
           destination.eventType == "pair_accepted" {
            await store.refreshRelationshipFromPush()
        }
        return result == .success ? .newData : .failed
    }

    func handleNotificationResponse(_ userInfo: [AnyHashable: Any]) async {
        guard let destination = NotificationDestination(userInfo: userInfo) else { return }
        if destination.eventType == "pair_accepted" {
            await store?.refreshRelationshipFromPush()
        } else {
            _ = await store?.synchronizeFromPush()
        }
        pendingDestination = destination
    }

    func consumeDestination() {
        pendingDestination = nil
    }

    private func uploadRegistrationIfPossible() async {
        guard !isUploading,
              let token = deviceToken,
              let store,
              store.shouldRegisterPushDevice,
              store.currentUser != nil,
              let deviceId = store.notificationDeviceIdentifier()
        else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            _ = try await store.api.registerPushDevice(
                deviceId: deviceId,
                request: PushDeviceRegistrationRequest(
                    token: token,
                    environment: Self.apnsEnvironment,
                    locale: selectedLocaleIdentifier,
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                    appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
                )
            )
            await updatePreferences()
            registrationError = nil
        } catch {
            registrationError = error.localizedDescription
        }
    }

    private func updatePreferences() async {
        guard let store,
              store.shouldRegisterPushDevice,
              store.currentUser != nil,
              let deviceId = store.notificationDeviceIdentifier()
        else { return }
        do {
            _ = try await store.api.updatePushPreferences(
                deviceId: deviceId,
                request: PushPreferenceRequest(
                    collaborationEnabled: collaborationEnabled,
                    remindersEnabled: remindersEnabled
                )
            )
        } catch {
            registrationError = error.localizedDescription
        }
    }

    private var selectedLocaleIdentifier: String {
        guard let language else { return Locale.autoupdatingCurrent.identifier }
        return language.selection == .system
            ? Locale.autoupdatingCurrent.identifier
            : language.selection.rawValue
    }

    private static var apnsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}
