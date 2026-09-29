import SwiftUI

/// Behind the grid: the grouped background, washed faintly amber once arrival
/// has closed (so a tap meaning "late" is felt, not just read), and on today
/// the color of the sky at this hour fading down from the top.
struct AssistantBackdrop: View {
    let isToday: Bool
    let isLate: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            AssistantBackdrop.base(isLate: isLate)
            if isToday {
                // The sky moves slowly; every five minutes is plenty.
                TimelineView(.periodic(from: .now, by: 300)) { context in
                    LinearGradient(
                        colors: [
                            AssistantSky.tint(at: context.date).color.opacity(colorScheme == .dark ? 0.22 : 0.34),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 280)
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.4), value: isLate)
        .animation(.smooth(duration: 0.4), value: isToday)
    }

    /// The background without the sky: also under the fade above the bar.
    static func base(isLate: Bool) -> some View {
        ZStack {
            Color(.systemGroupedBackground)
            Color.lateAmber.opacity(isLate ? 0.07 : 0)
        }
    }
}

/// A day with no school: a picture for the kind of day, a title, and on
/// today a word to the assistant. Only a holiday offers Check Again (the
/// guide may take it off the calendar); a weekend is a weekend.
struct AssistantDayOffView: View {
    let dayOff: AssistantAttendanceViewModel.DayOff
    let isToday: Bool
    let onCheckAgain: () -> Void

    @State private var appeared = false

    var body: some View {
        let art = AssistantDayOffArt.art(for: dayOff)
        VStack(spacing: 14) {
            Image(systemName: art.symbol)
                .font(.system(size: 64))
                .foregroundStyle(art.color.gradient)
                .symbolEffect(.bounce, value: appeared)
                .accessibilityHidden(true)
            Text(art.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(AssistantDayOffArt.message(for: dayOff, isToday: isToday, name: ClassroomIdentity.displayName))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if case .holiday = dayOff {
                Button("Check Again", action: onCheckAgain)
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .onAppear { appeared.toggle() }
    }
}
