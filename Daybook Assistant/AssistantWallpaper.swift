import SwiftUI

/// What sits behind the grid, chosen in Classroom → Background. Hers alone:
/// kept in this iPhone's defaults, never synced to the guide.
///
/// The marks are carried by the tiles' shapes (solid, outlined, dashed), and
/// the outlined and dashed ones show what's behind them. So only Sky and Plain
/// leave the tiles as they are; every other background gets frosted tiles
/// (`isQuiet`).
enum AssistantWallpaper: String, CaseIterable, Identifiable {
    case sky
    case cosmic
    case seasons
    case beadChains
    case pinkTower
    case plain
    case photo

    static let key = "Assistant.wallpaper"
    static let standard = AssistantWallpaper.sky

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sky: return "Sky"
        case .cosmic: return "Cosmic"
        case .seasons: return "Seasons"
        case .beadChains: return "Bead Chains"
        case .pinkTower: return "Pink Tower"
        case .plain: return "Plain"
        case .photo: return "Photo"
        }
    }

    /// Sky and Plain are calm enough that an outlined tile reads on them as
    /// it is; the rest frost the unmarked and absent tiles.
    var isQuiet: Bool { self == .sky || self == .plain }

    /// The background a stored value names. Anything unknown, or Photo with
    /// no photo saved, is Sky. Looks for the photo on disk only when the
    /// value is Photo: the grid asks on every redraw.
    static func resolved(_ raw: String?) -> AssistantWallpaper {
        resolved(raw, photoExists: raw == photo.rawValue && AssistantWallpaperPhoto.shared.hasPhoto)
    }

    static func resolved(_ raw: String?, photoExists: Bool) -> AssistantWallpaper {
        guard let raw, let wallpaper = AssistantWallpaper(rawValue: raw) else { return standard }
        if wallpaper == .photo && !photoExists { return standard }
        return wallpaper
    }

    // MARK: - Seasons

    enum Season: Equatable {
        case autumn, winter, spring, summer
    }

    /// The season of the day on screen (northern school year): stepping into
    /// December shows winter.
    static func season(for date: Date, calendar: Calendar = .current) -> Season {
        switch calendar.component(.month, from: date) {
        case 9, 10, 11: return .autumn
        case 12, 1, 2: return .winter
        case 3, 4, 5: return .spring
        default: return .summer
        }
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// Whether the grid sits on Sky or Plain: tiles keep their solid card and
    /// clear absence. False frosts them so their shapes read on a picture.
    @Entry var assistantBackdropIsQuiet = true
}
