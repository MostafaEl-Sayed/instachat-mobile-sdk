#if os(iOS)
import CoreLocation
import MapKit
import SwiftUI

struct MapLocationPickerView: View {
  @ObservedObject var locationProvider: CurrentLocationProvider
  var onSend: (InstaChatLocation) -> Void
  var onCancel: () -> Void

  @State private var region = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
    span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 120)
  )
  @State private var hasSelection = false
  @State private var isLocating = false
  @State private var isResolving = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      ZStack {
        Map(
          coordinateRegion: Binding(
            get: { region },
            set: { newRegion in
              region = newRegion
              hasSelection = true
            }
          ),
          interactionModes: .all
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
              mapZoomButton(systemImage: "plus", factor: 0.55)
              Divider().frame(width: 28)
              mapZoomButton(systemImage: "minus", factor: 1.8)
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

  private func mapZoomButton(systemImage: String, factor: Double) -> some View {
    Button {
      region.span = MKCoordinateSpan(
        latitudeDelta: min(max(region.span.latitudeDelta * factor, 0.002), 160),
        longitudeDelta: min(max(region.span.longitudeDelta * factor, 0.002), 160)
      )
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
      region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
      )
      hasSelection = true
    } catch {
      errorMessage = locationProvider.userFacingMessage(for: error)
    }
  }

  private func sendSelectedLocation() {
    guard hasSelection else {
      return
    }
    let coordinate = region.center
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
#endif
