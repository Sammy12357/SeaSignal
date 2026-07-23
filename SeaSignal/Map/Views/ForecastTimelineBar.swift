import SwiftUI

enum ForecastTimeline {
    static let minimumOffset = -6
    static let maximumOffset = 72
    static let step = 3

    static func clamped(_ offset: Int) -> Int {
        min(maximumOffset, max(minimumOffset, offset))
    }

    static func nextOffset(after offset: Int) -> Int? {
        let next = clamped(offset) + step
        return next <= maximumOffset ? next : nil
    }
}

struct ForecastTimelineBar: View {
    @Binding var offsetHours: Int
    let validAt: Date?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlaying = false

    private var displayedDate: Date {
        validAt ?? Calendar.current.date(byAdding: .hour, value: offsetHours, to: Date()) ?? Date()
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.subheadline.weight(.semibold))
                    Text(displayedDate.formatted(.dateTime.hour().minute()))
                        .font(.title3.weight(.bold))
                }
                Spacer()
                playbackButton
                stepButton(hours: -ForecastTimeline.step, icon: "chevron.left", title: "−3h")
                stepButton(hours: ForecastTimeline.step, icon: "chevron.right", title: "+3h", iconAfter: true)
            }

            Slider(
                value: Binding(
                    get: { Double(offsetHours) },
                    set: {
                        isPlaying = false
                        offsetHours = ForecastTimeline.clamped(Int($0 / Double(ForecastTimeline.step)) * ForecastTimeline.step)
                    }
                ),
                in: Double(ForecastTimeline.minimumOffset)...Double(ForecastTimeline.maximumOffset),
                step: Double(ForecastTimeline.step)
            )
            .tint(.oceanBlue)
            .accessibilityLabel("Forecast time")
            .accessibilityValue(displayedDate.formatted(.dateTime.weekday().hour().minute()))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .task(id: isPlaying) {
            guard isPlaying, !reduceMotion else { return }
            while !Task.isCancelled, isPlaying {
                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled, isPlaying else { return }
                guard let next = ForecastTimeline.nextOffset(after: offsetHours) else {
                    isPlaying = false
                    return
                }
                offsetHours = next
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { isPlaying = false }
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { isPlaying = false }
        }
    }

    private var playbackButton: some View {
        Button {
            if offsetHours >= ForecastTimeline.maximumOffset {
                offsetHours = 0
            }
            isPlaying.toggle()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.deepNavy)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(reduceMotion)
        .accessibilityLabel(isPlaying ? "Pause forecast playback" : "Play forecast timeline")
        .accessibilityHint(reduceMotion ? "Unavailable while Reduce Motion is enabled" : "Advances the forecast by three hours")
    }

    private func stepButton(hours: Int, icon: String, title: String, iconAfter: Bool = false) -> some View {
        Button {
            isPlaying = false
            offsetHours = ForecastTimeline.clamped(offsetHours + hours)
        } label: {
            HStack(spacing: 5) {
                if !iconAfter { Image(systemName: icon) }
                Text(title)
                if iconAfter { Image(systemName: icon) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.deepNavy)
            .frame(height: 42)
            .padding(.horizontal, 8)
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(hours < 0 ? offsetHours <= ForecastTimeline.minimumOffset : offsetHours >= ForecastTimeline.maximumOffset)
    }
}
