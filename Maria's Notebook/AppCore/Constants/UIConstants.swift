import SwiftUI

enum UIConstants {
    static let sidebarWidth: CGFloat = 280
    static let headerHorizontalPadding: CGFloat = 16
    static let headerVerticalPadding: CGFloat = 10

    static let contentHorizontalPadding: CGFloat = 16
    static let contentVerticalPadding: CGFloat = 20

    static let gridColumnSpacing: CGFloat = 24
    static let dayColumnSpacing: CGFloat = 14

    static let dayHeaderApproxHeight: CGFloat = 40
    static let labelHeight: CGFloat = 18
    static let minDropZoneTotalHeight: CGFloat = 220

    static let dropZoneCornerRadius: CGFloat = 18
    static let dropZoneStrokeDash: [CGFloat] = [6, 6]
    static let dropZoneInnerPadding: CGFloat = 12

    static let ageIndicatorWidth: CGFloat = 3

    static let morningHour: Int = 9
    static let afternoonHour: Int = 14

    static let planningWindowDays: Int = 5
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
        /// Note editor sheets
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
        
        /// 32pt - Extra large icon size
        static let iconSizeXLarge: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    
    /// Standardized corner radius values
    enum CornerRadius {
        /// 6pt - Small corner radius
        nonisolated static let small: CGFloat = 6
        
        /// 8pt - Medium corner radius
        nonisolated static let medium: CGFloat = 8
        
        /// 12pt - Large corner radius (cards)
        nonisolated static let large: CGFloat = 12
        
        /// 16pt - Extra large corner radius
        nonisolated static let extraLarge: CGFloat = 16
        
        /// 20pt - Extra extra large corner radius
        nonisolated static let xxLarge: CGFloat = 20
    }
    
    // MARK: - Stroke & Border Widths
    
    /// Standardized stroke and border widths
    enum StrokeWidth {
        /// 1pt - Thin strokes and borders
        nonisolated static let thin: CGFloat = 1
        
        /// 1.5pt - Regular strokes
        nonisolated static let regular: CGFloat = 1.5
        
        /// 2pt - Thick strokes for emphasis
        nonisolated static let thick: CGFloat = 2
        
        /// 3pt - Extra thick for strong emphasis
        nonisolated static let extraThick: CGFloat = 3
    }
    
    // MARK: - Line Limits
    
    /// Standardized line limit values for text
    enum LineLimit {
        /// 1 line - Single line of text
        static let single: Int = 1
        
        /// 2 lines - Double line of text
        static let double: Int = 2
        
        /// 3 lines - Triple line of text
        static let triple: Int = 3
        
        /// 4 lines - Quad line of text
        static let quad: Int = 4
    }
    
    // MARK: - Z-Index
    
    /// Standardized z-index values for layering
    enum ZIndex {
        /// 0 - Background layer
        static let background: Double = 0
        
        /// 1 - Base content layer
        static let base: Double = 1
        
        /// 10 - Overlay layer
        static let overlay: Double = 10
        
        /// 100 - Modal layer
        static let modal: Double = 100
        
        /// 1000 - Top-most layer (alerts, tooltips)
        static let topmost: Double = 1000
    }
    
    // MARK: - Animation Durations
    
    /// Standardized animation timing
    enum AnimationDuration {
        /// 0s - Instant (no animation)
        static let instant: Double = 0
        
        /// 0.1s - Very fast animations
        static let veryFast: Double = 0.1
        
        /// 0.15s - Fast animations
        static let fast: Double = 0.15
        
        /// 0.2s - Quick animations
        static let quick: Double = 0.2
        
        /// 0.25s - Standard animations
        static let standard: Double = 0.25
        
        /// 0.3s - Normal animations
        static let normal: Double = 0.3
        
        /// 0.5s - Slow animations
        static let slow: Double = 0.5
    }
    
    // MARK: - Spring Animations
    
    /// Standardized spring animation configurations
    enum SpringAnimation {
        /// Standard spring: response 0.25, damping 0.85
        static let standard = Animation.spring(response: 0.25, dampingFraction: 0.85)
        
        /// Bouncy spring: response 0.3, damping 0.7
        static let bouncy = Animation.spring(response: 0.3, dampingFraction: 0.7)
        
        /// Smooth spring: response 0.35, damping 0.9
        static let smooth = Animation.spring(response: 0.35, dampingFraction: 0.9)
        
        /// Interactive spring: response 0.16, damping 0.85
        static let interactive = Animation.interactiveSpring(response: 0.16, dampingFraction: 0.85)
        
        /// Gentle spring: response 0.35, damping 0.85, blend 0.1
        static let gentle = Animation.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)
    }
    
    // MARK: - Timing Delays
    
    /// Standardized delay durations for UI operations
    enum TimingDelay {
        /// 100ms - Very short delay
        static let veryShort: UInt64 = 100_000_000  // nanoseconds
        
        /// 200ms - Short delay
        static let short: UInt64 = 200_000_000
        
        /// 250ms - Debounce delay
        static let debounce: UInt64 = 250_000_000
        
        /// 300ms - Standard delay
        static let standard: UInt64 = 300_000_000
        
        /// 400ms - Medium delay
        static let medium: UInt64 = 400_000_000
        
        /// 600ms - Long delay
        static let long: UInt64 = 600_000_000
        
        /// 1.5s - Toast/message duration
        static let toast: UInt64 = 1_500_000_000
        
        /// 2s - Short message display
        static let shortMessage: UInt64 = 2_000_000_000
        
        /// 3s - Standard message display
        static let message: UInt64 = 3_000_000_000
    }
    
    // MARK: - Data Limits
    
    /// Standardized limits for data fetching and display
    enum DataLimit {
        // Date windows (in days)
        static let recentDays: Int = 7
        static let monthDays: Int = 30
        static let quarterDays: Int = 90
        static let yearDays: Int = 365
        static let twoYearDays: Int = 730
        
        // Fetch limits
        static let smallBatch: Int = 100
        static let mediumBatch: Int = 500
        static let largeBatch: Int = 1000
        
        // UI limits
        static let maxBackupRetention: Int = 50
        static let maxStepperValue: Int = 60
        static let maxWarningDays: Int = 30
    }
    
    // MARK: - Stroke Patterns
    
    /// Standardized dash patterns for strokes
    enum StrokePattern {
        /// [6, 6] - Standard dashed line
        static let dashed: [CGFloat] = [6, 6]
        
        /// [6, 4] - Tight dashed line
        static let dashedTight: [CGFloat] = [6, 4]
        
        /// [4, 4] - Small dashed line
        static let dashedSmall: [CGFloat] = [4, 4]
        
        /// [5] - Single dash
        static let single: [CGFloat] = [5]
    }
}
