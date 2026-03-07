import SwiftUI

/// Grid view showing a weekly lesson plan with columns for each weekday.
/// Cells display compact lesson cards with student initials and subject color coding.
struct WeekPlanOverviewView: View {
    let weekPlan: WeekPlan
    var onAcceptRecommendation: ((UUID) -> Void)?
    var onRejectRecommendation: ((UUID) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary
            if !weekPlan.summary.isEmpty {
                Text(weekPlan.summary)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            
            // Week grid
            #if os(macOS)
            macOSGrid
            #else
            iOSGrid
            #endif
            
            // Grouping suggestions
            if !weekPlan.groupings.isEmpty {
                groupingSuggestionsSection
            }
        }
    }
    
    // MARK: - macOS Grid (horizontal columns)
    
    #if os(macOS)
    private var macOSGrid: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(weekPlan.days) { day in
                dayColumn(day)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    #endif
    
    // MARK: - iOS Grid (vertical stack)
    
    private var iOSGrid: some View {
        VStack(spacing: 12) {
            ForEach(weekPlan.days) { day in
                dayRow(day)
            }
        }
    }
    
    // MARK: - Day Column (macOS)
    
    private func dayColumn(_ day: WeekPlan.DayPlanEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Day header
            Text(shortDayName(day.dayName))
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            
            if day.recommendations.isEmpty {
                Text("No lessons")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(day.recommendations) { rec in
                    compactLessonCard(rec)
                }
            }
            
            Spacer(minLength: 0)
        }
    }
    
    // MARK: - Day Row (iOS)
    
    private func dayRow(_ day: WeekPlan.DayPlanEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.dayName)
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            if day.recommendations.isEmpty {
                Text("No lessons scheduled")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(day.recommendations) { rec in
                    compactLessonCard(rec)
                }
            }
        }
        .padding(10)
        .background(.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
    
    // MARK: - Compact Lesson Card
    
    // swiftlint:disable:next function_body_length
    private func compactLessonCard(_ rec: LessonRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(AppColors.color(forSubject: rec.subject))
                    .frame(width: 6, height: 6)
                
                Text(rec.lessonName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(2)
            }
            
            // Student initials
            HStack(spacing: 2) {
                ForEach(rec.studentNames, id: \.self) { name in
                    Text(initials(from: name))
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.1), in: Capsule())
                }
            }
            
            // Accept/reject buttons
            if rec.decision == nil {
                HStack(spacing: 4) {
                    Button(action: { onAcceptRecommendation?(rec.id) }, label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10))
                    })
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.green)
                    
                    Button(action: { onRejectRecommendation?(rec.id) }, label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                    })
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.secondary)
                }
            } else {
                HStack(spacing: 2) {
                    Image(systemName: rec.decision == .accepted ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(rec.decision == .accepted ? .green : .secondary)
                    Text(rec.decision == .accepted ? "Accepted" : "Skipped")
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(rec.decision == .accepted ? .green : .secondary)
                }
            }
        }
        .padding(8)
        .background(cardBackground(for: rec), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(cardBorder(for: rec), lineWidth: 0.5)
        )
    }
    
    // MARK: - Grouping Suggestions
    
    private var groupingSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested Groupings")
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.semibold)
            
            ForEach(weekPlan.groupings) { grouping in
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(grouping.lessonName): \(grouping.studentNames.joined(separator: ", "))")
                            .font(.caption)
                        Text(grouping.rationale)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    // MARK: - Helpers
    
    private func shortDayName(_ fullName: String) -> String {
        let components = fullName.components(separatedBy: ",")
        return components.first?.trimmingCharacters(in: .whitespaces).prefix(3).description ?? fullName
    }
    
    private func initials(from name: String) -> String {
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))"
        }
        return String(name.prefix(2))
    }
    
    private func cardBackground(for rec: LessonRecommendation) -> some ShapeStyle {
        if rec.decision == .accepted { return AnyShapeStyle(Color.green.opacity(0.06)) }
        if rec.decision == .rejected { return AnyShapeStyle(Color.secondary.opacity(0.04)) }
        return AnyShapeStyle(Color.secondary.opacity(0.04))
    }
    
    private func cardBorder(for rec: LessonRecommendation) -> Color {
        if rec.decision == .accepted { return .green.opacity(0.3) }
        if rec.decision == .rejected { return .secondary.opacity(0.1) }
        return .secondary.opacity(0.1)
    }
}
