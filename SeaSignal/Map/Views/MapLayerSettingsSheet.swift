import SwiftUI

struct MapLayerSettingsSheet: View {
    @Binding var showWind: Bool
    @Binding var windLayerMode: WindLayerMode
    @Binding var windMode: WindDisplayMode
    @Binding var satellite: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Form {
                Section("Forecasts") {
                    Toggle(isOn: $showWind) {
                        Label("Wind", systemImage: "wind")
                            .font(.headline)
                    }
                    if showWind {
                        Picker("Wind data", selection: $windLayerMode) {
                            ForEach(WindLayerMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.systemImage).tag(mode)
                            }
                        }
                        Text(windLayerMode.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if windLayerMode.showsModeledWind {
                            Picker("Wind display", selection: $windMode) {
                                ForEach(WindDisplayMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            Text(windMode.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if reduceMotion, windMode != .colorOnly {
                                Label("Reduce Motion is enabled, so the wind field remains still.", systemImage: "accessibility")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Data sources") {
                    HStack {
                        Label(sourceTitle, systemImage: windLayerMode.systemImage)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.oceanBlue)
                    }
                    Text(sourceDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("Open-Meteo weather data", destination: URL(string: "https://open-meteo.com/")!)
                    Link("NOAA/NWS airport METARs", destination: URL(string: "https://aviationweather.gov/data/api/")!)
                    if windLayerMode.showsObservations {
                        Link("NOAA National Data Buoy Center", destination: URL(string: "https://www.ndbc.noaa.gov/")!)
                    }
                }

                Section("Map type") {
                    Picker("Map type", selection: $satellite) {
                        Text("Standard").tag(false)
                        Text("Satellite").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Map settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var sourceTitle: String {
        switch windLayerMode {
        case .hybrid: "Open-Meteo + NOAA NDBC"
        case .modeled: "Open-Meteo"
        case .observations: "NOAA NDBC"
        }
    }

    private var sourceDetail: String {
        switch windLayerMode {
        case .hybrid:
            "Modeled surface wind at 10 metres, checked against recent measured coastal observations."
        case .modeled:
            "Modeled surface wind at 10 metres for the selected forecast hour."
        case .observations:
            "Recent measured wind reported by NOAA buoys and coastal stations."
        }
    }
}
