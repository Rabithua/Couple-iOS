@preconcurrency import CoreLocation
import Observation

enum MemoryLocationStatus: Equatable {
    case idle
    case requestingAuthorization
    case locating
    case located
    case denied
    case servicesDisabled
    case failed
}

@MainActor
@Observable
final class MemoryLocationCoordinator: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private let geocoder: CLGeocoder
    private var availabilityTask: Task<Void, Never>?
    private var geocodingTask: Task<Void, Never>?
    private var geocodingTimeoutTask: Task<Void, Never>?
    private var captureRequested = false
    private var servicesChecked = false

    private(set) var status: MemoryLocationStatus = .idle
    private(set) var location: NoteLocation?
    private(set) var errorMessage: String?

    var isCapturing: Bool {
        status == .requestingAuthorization || status == .locating
    }

    init(
        manager: CLLocationManager = CLLocationManager(),
        geocoder: CLGeocoder = CLGeocoder()
    ) {
        self.manager = manager
        self.geocoder = geocoder
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func prepare(existingLocation: NoteLocation?, automaticallyCapture: Bool) {
        cancelPendingWork()
        location = existingLocation
        status = existingLocation == nil ? .idle : .located
        errorMessage = nil
        if automaticallyCapture { captureCurrentLocation() }
    }

    func captureCurrentLocation() {
        cancelPendingWork()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-location") {
            location = NoteLocation(latitude: 30.274_084_8, longitude: 120.155_070_7, name: "西湖")
            status = .located
            errorMessage = nil
            return
        }
#endif
        captureRequested = true
        errorMessage = nil
        status = .locating
        availabilityTask = Task { [weak self] in
            let servicesEnabled = await Task.detached {
                CLLocationManager.locationServicesEnabled()
            }.value
            guard let self, !Task.isCancelled, captureRequested else { return }
            availabilityTask = nil
            guard servicesEnabled else {
                finish(with: .servicesDisabled)
                return
            }
            servicesChecked = true
            continueCapture()
        }
    }

    private func continueCapture() {
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .requestingAuthorization
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocation()
        case .denied, .restricted:
            finish(with: .denied)
        @unknown default:
            finish(with: .failed)
        }
    }

    func removeLocation() {
        cancelPendingWork()
        location = nil
        status = .idle
        errorMessage = nil
    }

    func cancelPendingWork() {
        captureRequested = false
        servicesChecked = false
        availabilityTask?.cancel()
        availabilityTask = nil
        geocodingTask?.cancel()
        geocodingTask = nil
        geocodingTimeoutTask?.cancel()
        geocodingTimeoutTask = nil
        geocoder.cancelGeocode()
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard captureRequested, servicesChecked else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocation()
        case .denied, .restricted:
            finish(with: .denied)
        case .notDetermined:
            status = .requestingAuthorization
        @unknown default:
            finish(with: .failed)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard captureRequested,
              let current = locations.last(where: {
                  $0.horizontalAccuracy >= 0
                      && $0.timestamp.timeIntervalSinceNow > -120
              })
        else {
            finish(
                with: .failed,
                message: AppLocalization.string("没有获取到可用的位置，请重试")
            )
            return
        }

        let coordinate = current.coordinate
        let pendingLocation = NoteLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            name: nil
        )
        location = pendingLocation
        geocodingTask?.cancel()
        geocodingTimeoutTask?.cancel()
        geocodingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.geocoder.cancelGeocode()
        }
        geocodingTask = Task { [weak self] in
            guard let self else { return }
            let name = await reverseGeocodedName(for: current)
            guard !Task.isCancelled else { return }
            geocodingTimeoutTask?.cancel()
            geocodingTimeoutTask = nil
            location = NoteLocation(
                latitude: pendingLocation.latitude,
                longitude: pendingLocation.longitude,
                name: name
            )
            finish(with: .located)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let status: MemoryLocationStatus
        if let locationError = error as? CLError, locationError.code == .denied {
            status = .denied
        } else {
            status = .failed
        }
        finish(with: status, message: error.localizedDescription)
    }

    private func requestLocation() {
        status = .locating
        manager.requestLocation()
    }

    private func reverseGeocodedName(for location: CLLocation) async -> String? {
        do {
            let placemark = try await geocoder.reverseGeocodeLocation(
                location,
                preferredLocale: .current
            ).first
            return [placemark?.name, placemark?.subLocality, placemark?.locality]
                .compactMap { value in
                    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed?.isEmpty == false ? trimmed : nil
                }
                .first
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    private func finish(with status: MemoryLocationStatus, message: String? = nil) {
        captureRequested = false
        self.status = status
        errorMessage = message
    }
}
