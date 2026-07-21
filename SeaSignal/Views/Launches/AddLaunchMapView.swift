import MapKit
import SwiftUI

struct AddLaunchMapView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: LaunchStore
    @State private var name = ""
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapReader { proxy in
                    Map(position: $camera) {
                        if let coordinate {
                            Annotation("New launch", coordinate: coordinate, anchor: .bottom) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 38))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color.oceanBlue)
                                    .shadow(radius: 4)
                                    .gesture(
                                        DragGesture(coordinateSpace: .local)
                                            .onChanged { value in
                                                if let updated = proxy.convert(value.location, from: .local) {
                                                    self.coordinate = updated
                                                }
                                            }
                                    )
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                if let selected = proxy.convert(value.location, from: .local) {
                                    coordinate = selected
                                }
                            }
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Tap the map to place a launch pin, then drag it for precision.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("Launch name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        guard let coordinate else { return }
                        isSaving = true
                        Task {
                            await store.addPinnedLaunch(name: name, coordinate: coordinate)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            if isSaving { ProgressView().tint(.white) }
                            Text(isSaving ? "Saving launch…" : "Save and favorite launch")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(coordinate == nil || isSaving)
                }
                .padding()
                .background(.regularMaterial)
            }
            .navigationTitle("Pin a boat launch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let current = store.currentCoordinate {
                    coordinate = current
                    camera = .region(MKCoordinateRegion(
                        center: current,
                        latitudinalMeters: 30_000,
                        longitudinalMeters: 30_000
                    ))
                }
            }
        }
    }
}

