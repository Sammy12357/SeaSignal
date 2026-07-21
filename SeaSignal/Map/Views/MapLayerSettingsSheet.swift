import SwiftUI

struct MapLayerSettingsSheet: View {
    @Binding var showWind: Bool
    @Binding var windMode: WindDisplayMode
    @Binding var satellite: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Forecasts") {
                    Toggle(isOn: $showWind) {
                        Label("Wind", systemImage: "wind")
                            .font(.headline)
                    }
                    if showWind {
                        Picker("Wind display", selection: $windMode) {
                            ForEach(WindDisplayMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        Text(windMode.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Forecast model") {
                    HStack {
                        Label("Open-Meteo Forecast", systemImage: "cloud.sun.fill")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.oceanBlue)
                    }
                    Text("Surface wind at 10 metres, updated from the selected forecast hour.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
}
