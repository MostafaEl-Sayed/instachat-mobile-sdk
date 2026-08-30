import Foundation
#if canImport(CoreLocation)
import CoreLocation

@MainActor
final class CurrentLocationProvider: NSObject, ObservableObject {
  private let manager = CLLocationManager()
  private let geocoder = CLGeocoder()
  private var continuation: CheckedContinuation<CLLocation, Error>?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  func currentLocation(language: InstaChatLanguage = .devicePreferred) async throws -> InstaChatLocation {
    let location = try await requestLocation()
    let name = await reverseGeocodedName(for: location, language: language)

    return InstaChatLocation(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      name: name ?? InstaChatLocalizer(language: language).text("Current location")
    )
  }

  func selectedLocation(latitude: Double, longitude: Double, language: InstaChatLanguage = .devicePreferred) async -> InstaChatLocation {
    let location = CLLocation(latitude: latitude, longitude: longitude)
    let name = await reverseGeocodedName(for: location, language: language)

    return makeSelectedMapLocation(latitude: latitude, longitude: longitude, name: name, language: language)
  }

  func userFacingMessage(for error: Error, language: InstaChatLanguage = .devicePreferred) -> String {
    if let locationError = error as? CurrentLocationError {
      return locationError.message(language: language)
    }
    if let coreLocationError = error as? CLError,
       coreLocationError.code == .locationUnknown {
      return CurrentLocationError.unavailable.message(language: language)
    }
    return InstaChatLocalizer(language: language).text("Your current location could not be found. Choose a location manually on the map or try again.")
  }

  private func requestLocation() async throws -> CLLocation {
    guard CLLocationManager.locationServicesEnabled() else {
      throw CurrentLocationError.servicesDisabled
    }

    guard continuation == nil else {
      throw CurrentLocationError.requestInProgress
    }

    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      switch authorizationStatus {
      case .authorizedAlways, .authorizedWhenInUse:
        manager.requestLocation()
      case .notDetermined:
        manager.requestWhenInUseAuthorization()
      case .denied, .restricted:
        finish(with: .failure(CurrentLocationError.permissionDenied))
      @unknown default:
        finish(with: .failure(CurrentLocationError.permissionDenied))
      }
    }
  }

  private var authorizationStatus: CLAuthorizationStatus {
    #if os(iOS) || os(macOS)
    return manager.authorizationStatus
    #else
    return CLLocationManager.authorizationStatus()
    #endif
  }

  private func reverseGeocodedName(for location: CLLocation, language: InstaChatLanguage) async -> String? {
    do {
      let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: language.locale)
      guard let placemark = placemarks.first else {
        return nil
      }

      return [
        placemark.name,
        placemark.locality,
        placemark.administrativeArea,
        placemark.country
      ]
      .compactMap { $0?.isEmpty == false ? $0 : nil }
      .removingDuplicates()
      .joined(separator: ", ")
    } catch {
      return nil
    }
  }

  private func finish(with result: Result<CLLocation, Error>) {
    guard let continuation else {
      return
    }

    self.continuation = nil
    continuation.resume(with: result)
  }
}

func makeSelectedMapLocation(latitude: Double, longitude: Double, name: String? = nil, language: InstaChatLanguage = .devicePreferred) -> InstaChatLocation {
  InstaChatLocation(
    latitude: min(max(latitude, -90), 90),
    longitude: min(max(longitude, -180), 180),
    name: name ?? InstaChatLocalizer(language: language).text("Selected location")
  )
}

extension CurrentLocationProvider: CLLocationManagerDelegate {
  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      switch manager.authorizationStatus {
      case .authorizedAlways, .authorizedWhenInUse:
        manager.requestLocation()
      case .denied, .restricted:
        finish(with: .failure(CurrentLocationError.permissionDenied))
      case .notDetermined:
        break
      @unknown default:
        finish(with: .failure(CurrentLocationError.permissionDenied))
      }
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    Task { @MainActor in
      guard let location = locations.last else {
        finish(with: .failure(CurrentLocationError.unavailable))
        return
      }

      finish(with: .success(location))
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Task { @MainActor in
      if let locationError = error as? CLError,
         locationError.code == .locationUnknown {
        finish(with: .failure(CurrentLocationError.unavailable))
      } else {
        finish(with: .failure(error))
      }
    }
  }
}

enum CurrentLocationError: LocalizedError {
  case servicesDisabled
  case permissionDenied
  case unavailable
  case requestInProgress

  var errorDescription: String? {
    message(language: .devicePreferred)
  }

  func message(language: InstaChatLanguage) -> String {
    let strings = InstaChatLocalizer(language: language)
    switch self {
    case .servicesDisabled:
      return strings.text("Location Services are disabled. Enable Location Services to share your current location.")
    case .permissionDenied:
      return strings.text("Location permission is required to share your current location.")
    case .unavailable:
      return strings.text("Your current location could not be found. Choose a location manually on the map or try again.")
    case .requestInProgress:
      return strings.text("Current location is already being requested.")
    }
  }
}

private extension Array where Element: Hashable {
  func removingDuplicates() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
#endif
