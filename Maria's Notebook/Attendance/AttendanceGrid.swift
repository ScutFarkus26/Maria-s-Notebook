import SwiftUI
import SwiftData

struct AttendanceGrid: View {
    let students: [Student]
    let recordsByStudentID: [String: AttendanceRecord]
    let onCycleStatus: (Student) -> Void
    let onUpdateNote: (Student, String?) -> Void
    let onUpdateAbsenceReason: (Student, AbsenceReason) -> Void

    // Layout constants
    private let horizontalPadding: CGFloat = UIConstants.AttendanceGrid.horizontalPadding
    private let verticalPadding: CGFloat = UIConstants.AttendanceGrid.verticalPadding
    private let cardSpacing: CGFloat = UIConstants.AttendanceGrid.cardSpacing
    private let minCardWidth: CGFloat = UIConstants.AttendanceGrid.minCardWidth
    private let maxCardWidth: CGFloat = UIConstants.AttendanceGrid.maxCardWidth
    private let minCardHeight: CGFloat = UIConstants.AttendanceGrid.minCardHeight

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - (horizontalPadding * 2)
            let availableHeight = geometry.size.height - (verticalPadding * 2)

            // Calculate optimal grid layout
            let layout = calculateLayout(
                studentCount: students.count,
                availableWidth: availableWidth,
                availableHeight: availableHeight
            )

            let columns = Array(repeating: GridItem(.fixed(layout.cardWidth), spacing: cardSpacing), count: layout.columns)

            // Use ScrollView only when content doesn't fit
            if layout.needsScrolling {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .center, spacing: cardSpacing) {
                        ForEach(students, id: \.id) { student in
                            AttendanceCard(
                                student: student,
                                record: recordsByStudentID[student.cloudKitKey],
                                isEditing: true,
                                onTap: {
                                    onCycleStatus(student)
                                },
                                onEditNote: { newNote in
                                    onUpdateNote(student, newNote)
                                },
                                onSetAbsenceReason: { reason in
                                    onUpdateAbsenceReason(student, reason)
                                }
                            )
                            .frame(height: layout.cardHeight)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                }
            } else {
                VStack(spacing: 0) {
                    LazyVGrid(columns: columns, alignment: .center, spacing: cardSpacing) {
                        ForEach(students, id: \.id) { student in
                            AttendanceCard(
                                student: student,
                                record: recordsByStudentID[student.cloudKitKey],
                                isEditing: true,
                                onTap: {
                                    onCycleStatus(student)
                                },
                                onEditNote: { newNote in
                                    onUpdateNote(student, newNote)
                                },
                                onSetAbsenceReason: { reason in
                                    onUpdateAbsenceReason(student, reason)
                                }
                            )
                            .frame(height: layout.cardHeight)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)

                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Calculate the optimal grid layout to fill available space without scrolling
    private func calculateLayout(studentCount: Int, availableWidth: CGFloat, availableHeight: CGFloat) -> GridLayout {
        guard studentCount > 0, availableWidth > 0, availableHeight > 0 else {
            return GridLayout(columns: 1, rows: 1, cardWidth: minCardWidth, cardHeight: minCardHeight, needsScrolling: false)
        }

        // Try different column counts and find the best fit
        var bestLayout: GridLayout?

        // Calculate max possible columns based on minimum card width
        let maxPossibleColumns = max(1, Int((availableWidth + cardSpacing) / (minCardWidth + cardSpacing)))

        for cols in 1...maxPossibleColumns {
            let rows = Int(ceil(Double(studentCount) / Double(cols)))

            // Calculate card dimensions for this configuration
            let totalHorizontalSpacing = cardSpacing * CGFloat(cols - 1)
            let cardWidth = (availableWidth - totalHorizontalSpacing) / CGFloat(cols)

            let totalVerticalSpacing = cardSpacing * CGFloat(rows - 1)
            let cardHeight = (availableHeight - totalVerticalSpacing) / CGFloat(rows)

            // Check if this configuration is valid
            let isValidWidth = cardWidth >= minCardWidth && cardWidth <= maxCardWidth
            let isValidHeight = cardHeight >= minCardHeight

            if isValidWidth && isValidHeight {
                let layout = GridLayout(columns: cols, rows: rows, cardWidth: cardWidth, cardHeight: cardHeight, needsScrolling: false)

                // Prefer layouts that use more columns (wider cards look better)
                // but also consider height efficiency
                if let best = bestLayout {
                    // Prefer layout with more balanced aspect ratio and better space usage
                    let currentAspect = layout.cardWidth / layout.cardHeight
                    let bestAspect = best.cardWidth / best.cardHeight
                    let idealAspect: CGFloat = 2.5 // Prefer wider cards

                    let currentScore = abs(currentAspect - idealAspect)
                    let bestScore = abs(bestAspect - idealAspect)

                    if currentScore < bestScore {
                        bestLayout = layout
                    }
                } else {
                    bestLayout = layout
                }
            }
        }

        // Fallback: if no valid layout found, use minimum sizes with scrolling
        if bestLayout == nil {
            let cols = max(1, Int((availableWidth + cardSpacing) / (minCardWidth + cardSpacing)))
            let rows = Int(ceil(Double(studentCount) / Double(cols)))
            let totalHorizontalSpacing = cardSpacing * CGFloat(cols - 1)
            let cardWidth = min(maxCardWidth, max(minCardWidth, (availableWidth - totalHorizontalSpacing) / CGFloat(cols)))
            bestLayout = GridLayout(columns: cols, rows: rows, cardWidth: cardWidth, cardHeight: minCardHeight, needsScrolling: true)
        }

        return bestLayout!
    }
}

/// Represents a calculated grid layout
private struct GridLayout {
    let columns: Int
    let rows: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let needsScrolling: Bool
}
