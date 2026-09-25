import SwiftUI

nonisolated enum UIConstants {
    static let sidebarWidth: CGFloat = 280

    static let contentHorizontalPadding: CGFloat = 16

    static let dropZoneInnerPadding: CGFloat = 12

    static let ageIndicatorWidth: CGFloat = 3

    static let morningHour: Int = 9
    static let afternoonHour: Int = 14

    static let planningNavigationStepSchoolDays: Int = 7

    static let scheduleSpacingSeconds: Int = 1
    
    /// Delay in seconds before resetting navigation state
    /// Used after navigation actions to allow UI transitions to complete
    static let navigationResetDelay: TimeInterval = 0.1
    
    // MARK: - Attendance Grid Layout
    
    /// Layout constants for the attendance grid view
    enum AttendanceGrid {
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 16
        static let cardSpacing: CGFloat = 12
        static let minCardWidth: CGFloat = 120
        static let maxCardWidth: CGFloat = 280
        static let minCardHeight: CGFloat = 70
    }

    // MARK: - Window Size (macOS)

    /// Minimum window size for the main application window
    enum WindowSize {
        static let minWidth: CGFloat = 900
        static let minHeight: CGFloat = 600
    }

    // MARK: - Sheet Sizes (macOS)

    /// Standardized sheet size presets for consistent macOS window sizing
    enum SheetSize {
        /// Large sheets for detail views (StudentDetail, WorkDetail)
        static let large = CGSize(width: 720, height: 640)
        /// Medium sheets for editors and complex forms
        static let medium = CGSize(width: 520, height: 560)
        /// Small sheets for simple dialogs
        static let small = CGSize(width: 420, height: 480)
        /// Compact sheets for minimal dialogs
        static let compact = CGSize(width: 400, height: 400)
        /// CDNote editor sheets
        static let note = CGSize(width: 480, height: 560)
    }
    
    // MARK: - Opacity Constants
    
    /// Standardized opacity values for consistent visual hierarchy.
    /// Use these tokens instead of hardcoded opacity values throughout the app.
    enum OpacityConstants {
        /// 0.02 - Barely visible tint (ghost elements)
        static let ghost: Double = 0.02

        /// 0.03 - Whisper-level backgrounds
        static let whisper: Double = 0.03

        /// 0.04 - Trace-level tint (hover hints)
        static let trace: Double = 0.04

        /// 0.05 - Hint-level backgrounds (very subtle fills)
        static let hint: Double = 0.05

        /// 0.06 - Very faint backgrounds (subtle cards, improved contrast)
        static let veryFaint: Double = 0.06

        /// 0.08 - Subtle borders and dividers (improved contrast)
        nonisolated static let subtle: Double = 0.08

        /// 0.08 - Faint strokes and lines
        nonisolated static let faint: Double = 0.08

        /// 0.1 - Light overlays
        nonisolated static let light: Double = 0.1

        /// 0.12 - Medium accent backgrounds (status pills)
        nonisolated static let medium: Double = 0.12

        /// 0.15 - Accent highlights (selected states)
        nonisolated static let accent: Double = 0.15

        /// 0.2 - Moderate overlays (disabled states, muted elements)
        nonisolated static let moderate: Double = 0.2

        /// 0.25 - Quarter opacity (secondary badges, soft shadows)
        nonisolated static let quarter: Double = 0.25

        /// 0.3 - Semi-transparent (borders, dividers with presence)
        nonisolated static let semi: Double = 0.3

        /// 0.35 - Status backgrounds (more prominent)
        nonisolated static let statusBg: Double = 0.35

        /// 0.4 - Muted elements (dashed borders, secondary fills)
        nonisolated static let muted: Double = 0.4

        /// 0.5 - Half opacity (dimmed text, overlays)
        nonisolated static let half: Double = 0.5

        /// 0.7 - Prominent (strong overlays, near-opaque)
        nonisolated static let prominent: Double = 0.7

        /// 0.8 - Heavy (scrim overlays, strong presence)
        nonisolated static let heavy: Double = 0.8

        /// 0.85 - Near-solid (modal backgrounds)
        nonisolated static let nearSolid: Double = 0.85

        /// 0.9 - Almost opaque (frosted backgrounds)
        nonisolated static let almostOpaque: Double = 0.9

        /// 0.95 - Barely transparent
        nonisolated static let barelyTransparent: Double = 0.95
    }
    
    // MARK: - Card & Component Sizes
    
    /// Size constants for UI cards and components
    enum CardSize {
        /// 6pt - Horizontal padding for status pills
        static let statusPillHorizontal: CGFloat = 6
        
        /// 3pt - Vertical padding for status pills
        static let statusPillVertical: CGFloat = 3
        
        /// 80pt - Standard student avatar size
        static let studentAvatar: CGFloat = 80
        
        /// 16pt - Standard icon size
        static let iconSize: CGFloat = 16
        
        /// 24pt - Large icon size
        static let iconSizeLarge: CGFloat = 24
    }
    
    // MARK: - Corner Radius
    
    /// Standardized corner radius values.
    ///
    /// One case per value the app draws with; a site keeps the case that
    /// matches its radius exactly (see
    /// `Documentation/Implementation/design-system-migration.md`).
    enum CornerRadius {
        /// 1pt - Hairline accent bars (the 3 × 14 strip beside a checklist area name)
        nonisolated static let hairline: CGFloat = 1

        /// 3pt - Tiny corners on progress bars and swatches
        nonisolated static let tiny: CGFloat = 3

        /// 6pt - Small corner radius (checklist cells, tag badges, small tinted labels)
        nonisolated static let small: CGFloat = 6

        /// 8pt - Medium corner radius (compact rows, menu chips, progress bars)
        nonisolated static let medium: CGFloat = 8

        /// 10pt - Controls: search fields, text editors, compact work rows, toasts, tinted blocks
        nonisolated static let control: CGFloat = 10

        /// 12pt - Large corner radius (cards; `CardStyle.cornerRadius`)
        nonisolated static let large: CGFloat = 12

        /// 14pt - Tiles: roster and presentation cards, drop zones, grid focus rings
        nonisolated static let tile: CGFloat = 14

        /// 16pt - Extra large corner radius (student chips, detail panels)
        nonisolated static let extraLarge: CGFloat = 16

        /// 20pt - Hero panels (the mastery banner on a student's track detail)
        nonisolated static let hero: CGFloat = 20
    }
    
    // MARK: - Stroke & Border Widths
    
    /// Standardized stroke and border widths
    enum StrokeWidth {
        /// 1pt - Thin strokes and borders
        nonisolated static let thin: CGFloat = 1
        
        /// 1.5pt - Regular strokes
        nonisolated static let regular: CGFloat = 1.5
    }

    // MARK: - Animation Durations
    
    /// Standardized animation timing
    enum AnimationDuration {
        
        /// 0.15s - Fast animations
        static let fast: Double = 0.15
        
        /// 0.2s - Quick animations
        static let quick: Double = 0.2
        
        /// 0.25s - Standard animations
        static let standard: Double = 0.25
    }
    
    // MARK: - Spring Animations
    
    /// Standardized spring animation configurations
    enum SpringAnimation {
        /// Standard spring: response 0.25, damping 0.85
        static let standard = Animation.spring(response: 0.25, dampingFraction: 0.85)
        
        /// Bouncy spring: response 0.3, damping 0.7
        static let bouncy = Animation.spring(response: 0.3, dampingFraction: 0.7)
    }
}
