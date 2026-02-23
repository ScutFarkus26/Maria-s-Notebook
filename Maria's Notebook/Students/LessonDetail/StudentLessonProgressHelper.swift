import Foundation

// MARK: - Student Lesson Progress Helper

/// Helper for computing progress state for lesson presentations.
enum StudentLessonProgressHelper {

    // MARK: - Progress State Computation

    /// Determines if the "Just Presented" state is active.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the lesson is presented
    ///   - givenAt: The date when the lesson was given
    ///   - calendar: Calendar for date comparisons
    /// - Returns: True if just presented today
    static func isJustPresentedActive(
        isPresented: Bool,
        givenAt: Date?,
        calendar: Calendar
    ) -> Bool {
        guard isPresented else { return false }
        guard let date = givenAt else { return false }
        return calendar.isDateInToday(date)
    }

    /// Determines if the "Previously Presented" state is active.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the lesson is presented
    ///   - givenAt: The date when the lesson was given
    ///   - calendar: Calendar for date comparisons
    /// - Returns: True if presented but not today
    static func isPreviouslyPresentedActive(
        isPresented: Bool,
        givenAt: Date?,
        calendar: Calendar
    ) -> Bool {
        isPresented && !isJustPresentedActive(isPresented: isPresented, givenAt: givenAt, calendar: calendar)
    }

    /// Determines if the "Needs Another Presentation" state is active.
    ///
    /// - Parameters:
    ///   - needsAnotherPresentation: Whether another presentation is needed
    ///   - isPresented: Whether the lesson is presented
    /// - Returns: True if needs another and not presented
    static func isNeedsAnotherActive(
        needsAnotherPresentation: Bool,
        isPresented: Bool
    ) -> Bool {
        needsAnotherPresentation && !isPresented
    }
}
