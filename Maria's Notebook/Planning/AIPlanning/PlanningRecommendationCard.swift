import SwiftUI

/// Card view displaying a single AI-generated lesson recommendation.
/// Shows lesson name, subject tag, student names, confidence badge, and reasoning.
/// Provides accept/reject/ask-why actions.
struct PlanningRecommendationCard: View {
    let recommendation: LessonRecommendation
    var onAccept: () -> Void
    var onReject: () -> Void
    var onAskWhy: (() -> Void)?
    
    private var isDecided: Bool {
        recommendation.decision != nil
    }
    
    private var isAccepted: Bool {
        recommendation.decision == .accepted
    }
    
    private var isRejected: Bool {
        recommendation.decision == .rejected
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row: lesson name + confidence
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.lessonName)
                        .font(AppTheme.ScaledFont.body)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    
                    HStack(spacing: 6) {
                        subjectTag
                        if !recommendation.group.isEmpty {
                            Text(recommendation.group)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                confidenceBadge
            }
            
            // Student names
            if !recommendation.studentNames.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(recommendation.studentNames.joined(separator: ", "))
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            // Reasoning
            Text(recommendation.reasoning)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            
            // Suggested day
            if let day = recommendation.suggestedDay {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(day)
                        .font(.caption)
                }
                .foregroundStyle(.teal)
            }
            
            // Actions
            actionButtons
        }
        .padding(12)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: isDecided ? 2 : 0.5)
        )
    }
    
    // MARK: - Components
    
    private var subjectTag: some View {
        Text(recommendation.subject)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AppColors.color(forSubject: recommendation.subject).opacity(0.15), in: Capsule())
            .foregroundStyle(AppColors.color(forSubject: recommendation.subject))
    }
    
    private var confidenceBadge: some View {
        let pct = Int(recommendation.confidence * 100)
        return Text("\(pct)%")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(confidenceColor.opacity(0.15), in: Capsule())
            .foregroundStyle(confidenceColor)
    }
    
    private var confidenceColor: Color {
        if recommendation.confidence >= 0.8 { return .green }
        if recommendation.confidence >= 0.6 { return .orange }
        return .red
    }
    
    private var cardBackground: some ShapeStyle {
        if isAccepted { return AnyShapeStyle(Color.green.opacity(0.05)) }
        if isRejected { return AnyShapeStyle(Color.red.opacity(0.05)) }
        return AnyShapeStyle(Color.secondary.opacity(0.04))
    }
    
    private var borderColor: Color {
        if isAccepted { return .green.opacity(0.4) }
        if isRejected { return .red.opacity(0.3) }
        return .secondary.opacity(0.15)
    }
    
    private var actionButtons: some View {
        HStack(spacing: 8) {
            if !isDecided {
                Button(action: onAccept) {
                    Label("Accept", systemImage: "checkmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                
                Button(action: onReject) {
                    Label("Skip", systemImage: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                
                if let onAskWhy {
                    Button(action: onAskWhy) {
                        Label("Why?", systemImage: "questionmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: isAccepted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isAccepted ? .green : .secondary)
                    Text(isAccepted ? "Accepted" : "Skipped")
                        .font(.caption)
                        .foregroundStyle(isAccepted ? .green : .secondary)
                }
                
                Spacer()
                
                // Undo button
                Button(action: {
                    if isAccepted { onReject() } else { onAccept() }
                }) {
                    Text("Change")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }
}
