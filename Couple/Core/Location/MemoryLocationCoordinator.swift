@preconcurrency import CoreLocation
import Observation

enum MemoryLocationStatus: Equatable {
    case idle
    case requestingAuthorization
    case locating
    case resolvingName
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
    private let photoGeocoder: CLGeocoder
    private var availabilityTask: Task<Void, Never>?
    private var locationTimeoutTask: Task<Void, Never>?
    private var geocodingTask: Task<Void, Never>?
    private var geocodingTimeoutTask: Task<Void, Never>?
    private var captureRequested = false
    private var servicesChecked = false

    private(set) var status: MemoryLocationStatus = .idle
    private(set) var location: NoteLocation?
    private(set) var currentLocation: NoteLocation?
    private(set) var errorMessage: String?

    var isCapturing: Bool {
        status == .requestingAuthorization
            || status == .locating
            || status == .resolvingName
    }

    init(
        manager: CLLocationManager = CLLocationManager(),
        geocoder: CLGeocoder = CLGeocoder(),
        photoGeocoder: CLGeocoder = CLGeocoder()
    ) {
        self.manager = manager
        self.geocoder = geocoder
        self.photoGeocoder = photoGeocoder
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func prepare(existingLocation: NoteLocation?, automaticallyCapture: Bool) {
        cancelPendingWork()
        location = existingLocation
        currentLocation = nil
        status = existingLocation == nil ? .idle : .located
        errorMessage = nil
        if automaticallyCapture { captureCurrentLocation() }
    }

    func captureCurrentLocation() {
        cancelPendingWork()
        currentLocation = nil
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-location") {
            let resolvedLocation = NoteLocation(
                latitude: 30.274_084_8,
                longitude: 120.155_070_7,
                name: "西湖"
            )
            location = resolvedLocation
            currentLocation = resolvedLocation
            status = .located
            errorMessage = nil
            return
        }
#endif
        captureRequested = true
        errorMessage = nil
        status = .locating
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-location-timeout") {
            startLocationTimeout(after: .milliseconds(200))
            return
        }
#endif
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

    func usePhotoLocation(_ photoLocation: NoteLocation) {
        cancelPendingWork()
        location = photoLocation
        errorMessage = nil

        if let name = photoLocation.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            location = NoteLocation(
                latitude: photoLocation.latitude,
                longitude: photoLocation.longitude,
                name: name
            )
            status = .located
            return
        }

        status = .resolvingName
        resolveName(
            for: CLLocation(
                latitude: photoLocation.latitude,
                longitude: photoLocation.longitude
            ),
            pendingLocation: photoLocation,
            cacheAsCurrentLocation: false
        )
    }

    func useCurrentLocation() {
        guard let currentLocation else {
            captureCurrentLocation()
            return
        }
        cancelPendingWork()
        location = currentLocation
        status = .located
        errorMessage = nil
    }

    func resolvingPhotoLocationNames(_ photoLocations: [NoteLocation]) async -> [NoteLocation] {
        photoGeocoder.cancelGeocode()
        var resolvedLocations: [NoteLocation] = []
        resolvedLocations.reserveCapacity(photoLocations.count)

        for photoLocation in photoLocations {
            guard !Task.isCancelled else { return resolvedLocations }
            if let name = photoLocation.name?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                resolvedLocations.append(NoteLocation(
                    latitude: photoLocation.latitude,
                    longitude: photoLocation.longitude,
                    name: name
                ))
                continue
            }

            let name = await reverseGeocodedName(
                for: CLLocation(
                    latitude: photoLocation.latitude,
                    longitude: photoLocation.longitude
                ),
                using: photoGeocoder
            )
            guard !Task.isCancelled else { return resolvedLocations }
            resolvedLocations.append(NoteLocation(
                latitude: photoLocation.latitude,
                longitude: photoLocation.longitude,
                name: name
            ))
        }
        return resolvedLocations
    }

    func cancelPendingWork() {
        captureRequested = false
        servicesChecked = false
        availabilityTask?.cancel()
        availabilityTask = nil
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
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
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
        let pendingLocation = NoteLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            name: nil
        )
        resolveName(
            for: current,
            pendingLocation: pendingLocation,
            cacheAsCurrentLocation: true
        )
    }

    private func resolveName(
        for sourceLocation: CLLocation,
        pendingLocation: NoteLocation,
        cacheAsCurrentLocation: Bool
    ) {
        location = pendingLocation
        status = .resolvingName
        geocodingTask?.cancel()
        geocodingTimeoutTask?.cancel()
        geocodingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled else { return }
            geocodingTask?.cancel()
            geocodingTask = nil
            geocoder.cancelGeocode()
            location = nil
            finish(
                with: .failed,
                message: AppLocalization.string("没有获取到可用的位置，请重试")
            )
            geocodingTimeoutTask = nil
        }
        geocodingTask = Task { [weak self] in
            guard let self else { return }
            let name = await reverseGeocodedName(for: sourceLocation, using: geocoder)
            guard !Task.isCancelled else { return }
            geocodingTimeoutTask?.cancel()
            geocodingTimeoutTask = nil
            let resolvedLocation = NoteLocation(
                latitude: pendingLocation.latitude,
                longitude: pendingLocation.longitude,
                name: name
            )
            location = resolvedLocation
            if cacheAsCurrentLocation, name != nil {
                currentLocation = resolvedLocation
            }
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
        startLocationTimeout(after: .seconds(12))
        manager.requestLocation()
    }

    private func startLocationTimeout(after duration: Duration) {
        locationTimeoutTask?.cancel()
        locationTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled, captureRequested else { return }
            manager.stopUpdatingLocation()
            finish(
                with: .failed,
                message: AppLocalization.string("定位超时，请重试")
            )
        }
    }

    private func reverseGeocodedName(
        for location: CLLocation,
        using geocoder: CLGeocoder
    ) async -> String? {
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
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
        captureRequested = false
        self.status = status
        errorMessage = message
    }
}
