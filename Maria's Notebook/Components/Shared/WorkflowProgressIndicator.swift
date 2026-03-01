import SwiftUI

/// Progress indicator for presentation workflow showing completion status
struct WorkflowProgressIndicator: View {
    let totalStudents: Int
    let studentsWithUnderstanding: Int
    let studentsWithNotes: Int
    let hasGroupObservation: Bool
    
    private var progressPercentage: Double {
        let totalItems = 3.0 // understanding, notes, group observation
        var completed = 0.0
        
        if studentsWithUnderstanding == totalStudents {
            completed += 1.0
        }
        if studentsWithNotes > 0 {
            completed += 1.0
        }
        if hasGroupObservation {
            completed += 1.0
        }
        
        return completed / totalItems
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                // Understanding progress
                progressItem(
                    isComplete: studentsWithUnderstanding == totalStudents,
                    text: "\(studentsWithUnderstanding)/\(totalStudents) understanding set"
                )
                
                // Notes progress
                progressItem(
                    isComplete: studentsWithNotes > 0,
                    text: "\(studentsWithNotes)/\(totalStudents) with notes"
                )
                
                // Group observation
                progressItem(
                    isComplete: hasGroupObservation,
                    text: "Group notes"
                )
                
                Spacer()
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * progressPercentage, height: 6)
                }
            }
            .frame(height: 6)
        }
    }
    
    private func progressItem(isComplete: Bool, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? .green : .secondary)
                .font(.system(size: 14))
            Text(text)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
    }
}
