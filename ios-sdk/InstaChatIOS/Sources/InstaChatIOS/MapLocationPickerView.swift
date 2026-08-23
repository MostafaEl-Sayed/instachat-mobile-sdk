#if os(iOS)
import CoreLocation
import GoogleMaps
import SwiftUI

struct MapLocationPickerView: View {
  @ObservedObject var locationProvider: CurrentLocationProvider
  var onSend: (InstaChatLocation) -> Void
  var onCancel: () -> Void

  @State private var selectedCoordinate = CLLocationCoordinate2D(latitude: 20, longitude: 0)
  @State private var zoom: Float = 1.8
  @State private var hasSelection = false
  @State private var isLocating = false
  @State private var isResolving = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      ZStack {
        GoogleMapPickerSurface(
          coordinate: $selectedCoordinate,
          zoom: $zoom,
          onCameraMoved: {
            hasSelection = true
          }
        )
        .ignoresSafeArea(edges: .bottom)

        Image(systemName: "mappin")
          .font(.system(size: 34, weight: .semibold))
          .foregroundStyle(Color.red)
          .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
          .offset(y: -17)
          .accessibilityHidden(true)

        VStack {
          Spacer()
          HStack(alignment: .bottom) {
            Button {
              Task {
                await centerOnCurrentLocation()
              }
            } label: {
              Label(isLocating ? "Locating" : "My Location", systemImage: "location.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(.regularMaterial, in: Capsule())
            }
            .disabled(isLocating || isResolving)
            .accessibilityHint("Centers the map on your current location")

            Spacer()

            VStack(spacing: 0) {
              mapZoomButton(systemImage: "plus", delta: 1)
              Divider().frame(width: 28)
              mapZoomButton(systemImage: "minus", delta: -1)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          }
          .padding(16)
        }
      }
      .navigationTitle("Choose Location")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(isResolving ? "Sending..." : "Send") {
            sendSelectedLocation()
          }
          .disabled(!hasSelection || isLocating || isResolving)
        }
      }
      .alert("Location Unavailable", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK", role: .cancel) {
          errorMessage = nil
        }
      } message: {
        Text(errorMessage ?? "Try again or choose a location manually on the map.")
      }
    }
  }

  private func mapZoomButton(systemImage: String, delta: Float) -> some View {
    Button {
      zoom = min(max(zoom + delta, 1), 21)
      hasSelection = true
    } label: {
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .semibold))
        .frame(width: 44, height: 40)
    }
    .accessibilityLabel(systemImage == "plus" ? "Zoom in" : "Zoom out")
  }

  @MainActor
  private func centerOnCurrentLocation() async {
    guard !isLocating else {
      return
    }
    isLocating = true
    defer { isLocating = false }

    do {
      let location = try await locationProvider.currentLocation()
      selectedCoordinate = CLLocationCoordinate2D(
        latitude: location.latitude,
        longitude: location.longitude
      )
      zoom = 16
      hasSelection = true
    } catch {
      errorMessage = locationProvider.userFacingMessage(for: error)
    }
  }

  private func sendSelectedLocation() {
    guard hasSelection else {
      return
    }
    let coordinate = selectedCoordinate
    isResolving = true
    Task {
      let location = await locationProvider.selectedLocation(
        latitude: coordinate.latitude,
        longitude: coordinate.longitude
      )
      isResolving = false
      onSend(location)
    }
  }
}

private struct GoogleMapPickerSurface: UIViewRepresentable {
  @Binding var coordinate: CLLocationCoordinate2D
  @Binding var zoom: Float
  var onCameraMoved: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIView(context: Context) -> GMSMapView {
    let options = GMSMapViewOptions()
    options.camera = GMSCameraPosition(
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
      zoom: zoom
    )
    let mapView = GMSMapView(options: options)
    mapView.delegate = context.coordinator
    mapView.settings.compassButton = true
    mapView.settings.rotateGestures = true
    mapView.settings.scrollGestures = true
    mapView.settings.tiltGestures = true
    mapView.settings.zoomGestures = true
    mapView.padding = UIEdgeInsets(top: 0, left: 0, bottom: 74, right: 0)
    mapView.paddingAdjustmentBehavior = .never
    return mapView
  }

  func updateUIView(_ mapView: GMSMapView, context: Context) {
    context.coordinator.parent = self
    let camera = mapView.camera
    guard !camera.target.isApproximatelyEqual(to: coordinate) || abs(camera.zoom - zoom) > 0.01 else {
      return
    }

    context.coordinator.isApplyingSwiftUIUpdate = true
    mapView.animate(
      to: GMSCameraPosition(
        target: coordinate,
        zoom: zoom
      )
    )
  }

  final class Coordinator: NSObject, GMSMapViewDelegate {
    var parent: GoogleMapPickerSurface
    var isApplyingSwiftUIUpdate = false

    init(parent: GoogleMapPickerSurface) {
      self.parent = parent
    }

    func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
      let wasProgrammaticUpdate = isApplyingSwiftUIUpdate
      isApplyingSwiftUIUpdate = false
      parent.coordinate = position.target
      parent.zoom = position.zoom
      if !wasProgrammaticUpdate {
        parent.onCameraMoved()
      }
    }
  }
}

private extension CLLocationCoordinate2D {
  func isApproximatelyEqual(to other: CLLocationCoordinate2D) -> Bool {
    abs(latitude - other.latitude) < 0.000_001 &&
      abs(longitude - other.longitude) < 0.000_001
  }
}
#endif
