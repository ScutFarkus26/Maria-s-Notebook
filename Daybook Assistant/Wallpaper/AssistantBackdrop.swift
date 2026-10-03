import SwiftUI

/// Behind the grid: the background she chose (`AssistantWallpaper`), washed
/// faintly amber once arrival has closed (so a tap meaning "late" is felt, not
/// just read), and on Sky, on today, the color of the sky at this hour fading
/// down from the top.
struct AssistantBackdrop: View {
    let isToday: Bool
    let isLate: Bool
    /// The day on screen, for Seasons.
    var date = Date()
    /// How much of the class is here, 0 to 1, for Cosmic.
    var hereFraction: Double = 0
    /// Draws this background instead of her choice: the picker's previews.
    var wallpaper: AssistantWallpaper?
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AssistantWallpaper.key) private var wallpaperRaw = AssistantWallpaper.standard.rawValue

    var body: some View {
        let wallpaper = wallpaper ?? AssistantWallpaper.resolved(wallpaperRaw)
        ZStack(alignment: .top) {
            AssistantWallpaperView(wallpaper: wallpaper, date: date, hereFraction: hereFraction)
            if wallpaper == .sky, isToday {
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
            // Over every background: late should feel the same on each.
            Color.lateAmber.opacity(isLate ? (wallpaper.isQuiet ? 0.07 : 0.12) : 0)
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.4), value: isLate)
        .animation(.smooth(duration: 0.4), value: isToday)
        .animation(.smooth(duration: 0.6), value: hereFraction)
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
