import CoreLocation
import ImageIO
@preconcurrency import Photos

enum PhotoLocationExtractor {
    static func location(itemIdentifier: String?, imageData: Data) -> NoteLocation? {
        photoLibraryLocation(itemIdentifier: itemIdentifier)
            ?? imageMetadataLocation(imageData)
    }

    static func imageMetadataLocation(_ data: Data) -> NoteLocation? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else { return nil }

        return imageMetadataLocation(properties)
    }

    static func imageMetadataLocation(_ properties: [CFString: Any]) -> NoteLocation? {
        guard let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latitudeValue = number(gps[kCGImagePropertyGPSLatitude]),
              let longitudeValue = number(gps[kCGImagePropertyGPSLongitude])
        else { return nil }

        let latitude = signed(
            latitudeValue,
            reference: gps[kCGImagePropertyGPSLatitudeRef] as? String,
            negativeReference: "S"
        )
        let longitude = signed(
            longitudeValue,
            reference: gps[kCGImagePropertyGPSLongitudeRef] as? String,
            negativeReference: "W"
        )
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }

        return NoteLocation(latitude: latitude, longitude: longitude, name: nil)
    }

    private static func photoLibraryLocation(itemIdentifier: String?) -> NoteLocation? {
        guard let itemIdentifier else { return nil }
        let authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorization == .authorized || authorization == .limited,
              let location = PHAsset.fetchAssets(
                withLocalIdentifiers: [itemIdentifier],
                options: nil
              ).firstObject?.location
        else { return nil }

        return NoteLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            name: nil
        )
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func signed(
        _ value: Double,
        reference: String?,
        negativeReference: String
    ) -> Double {
        reference?.uppercased() == negativeReference ? -abs(value) : abs(value)
    }
}
