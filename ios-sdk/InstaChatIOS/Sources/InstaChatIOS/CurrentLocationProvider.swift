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

  func currentLocation() async throws -> InstaChatLocation {
    let location = try await requestLocation()
    let name = await reverseGeocodedName(for: location)

    return InstaChatLocation(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      name: name ?? "Current location"
    )
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

  private func reverseGeocodedName(for location: CLLocation) async -> String? {
    do {
      let placemarks = try await geocoder.reverseGeocodeLocation(location)
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
      finish(with: .failure(error))
    }
  }
}

enum CurrentLocationError: LocalizedError {
  case servicesDisabled
  case permissionDenied
  case unavailable
  case requestInProgress

  var errorDescription: String? {
    switch self {
    case .servicesDisabled:
      return "Location Services are disabled. Enable Location Services to share your current location."
    case .permissionDenied:
      return "Location permission is required to share your current location."
    case .unavailable:
      return "Your current location could not be found. Try again in a moment."
    case .requestInProgress:
      return "Current location is already being requested."
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
