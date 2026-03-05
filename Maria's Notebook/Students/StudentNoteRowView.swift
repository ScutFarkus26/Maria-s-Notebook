//
//  StudentNoteRowView.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 12/27/25.
//

import SwiftUI

struct StudentNoteRowView: View {
    let item: UnifiedNoteItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 1. Leading Icon with pin/follow-up indicators
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(item.color.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: iconName(for: item.source))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(item.color)
                }

                // Pin indicator
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppColors.warning)
                        .offset(x: 4, y: -4)
                }

                // Follow-up indicator
                if item.needsFollowUp {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppColors.destructive)
                        .offset(x: item.isPinned ? 4 : 4, y: item.isPinned ? 8 : -4)
                }
            }

            // 2. Center Content
            VStack(alignment: .leading, spacing: 6) {
                // Reporter header (if not from guide)
                if !isReportedByGuide {
                    reporterHeader
                }
                
                HStack(alignment: .firstTextBaseline) {
                    Text(item.contextText)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Text(formattedDate(item.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Tag badges
                if !item.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(item.tags, id: \.self) { tag in
                                TagBadge(tag: tag, compact: true)
                            }
                        }
                    }
                }

                Text(item.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true) // Ensures text wraps properly
                
                // Display image if available
                if let imagePath = item.imagePath {
                    imageView(for: imagePath)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(isReportedByGuide ? Color.clear : Color(white: 0.98))
        .contentShape(Rectangle()) // Ensures the whole row is tappable
    }
    
    // MARK: - Reporter Info
    
    private var isReportedByGuide: Bool {
        // If reportedBy is nil or "guide", consider it from the guide
        guard let reportedBy = item.reportedBy else { return true }
        return reportedBy.lowercased() == "guide" || reportedBy.isEmpty
    }
    
    @ViewBuilder
    private var reporterHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.bubble.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(reporterDisplayText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(0.1))
        )
    }
    
    private var reporterDisplayText: String {
        if let reporterName = item.reporterName, !reporterName.isEmpty {
            if let reportedBy = item.reportedBy, !reportedBy.isEmpty, reportedBy.lowercased() != "guide" {
                let role = reportedBy.capitalized
                return "\(role): \(reporterName)"
            }
            return reporterName
        } else if let reportedBy = item.reportedBy, !reportedBy.isEmpty, reportedBy.lowercased() != "guide" {
            let role = reportedBy.capitalized
            return "From \(role)"
        }
        return "From Assistant"
    }

    // MARK: - Helpers
    
    @ViewBuilder
    private func imageView(for imagePath: String) -> some View {
        // Use the new async component instead of direct PhotoStorageService calls
        AsyncCachedImage(filename: imagePath)
            .frame(maxWidth: 300, maxHeight: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 8)
    }

    private func iconName(for source: UnifiedNoteItem.Source) -> String {
        switch source {
        case .general: return "person.bubble.fill"
        case .lesson:  return "book.closed.fill"
        case .work:    return "doc.text.fill"
        case .meeting: return "person.2.fill"
        case .presentation: return "presentation.fill"
        case .attendance: return "calendar.badge.clock" // Added missing case
        }
    }

    private func formattedDate(_ date: Date) -> String {
        DateFormatters.mediumDateTimeRelative.string(from: date)
    }
    
}

// MARK: - Preview
#if DEBUG
struct StudentNoteRowView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            StudentNoteRowView(item: UnifiedNoteItem(
                id: UUID(),
                date: Date(),
                body: "Student showed great enthusiasm for the decimal system introduction today.",
                source: .lesson,
                contextText: "Decimal System",
                color: .green,
                associatedID: nil,
                tags: [TagHelper.createTag(name: "Academic", color: .blue)],
                includeInReport: false,
                needsFollowUp: false,
                imagePath: nil,
                reportedBy: nil,
                reporterName: nil,
                isPinned: true
            ))

            StudentNoteRowView(item: UnifiedNoteItem(
                id: UUID(),
                date: Date().addingTimeInterval(-86400),
                body: "Needs to focus more on handwriting clarity during follow-up work.",
                source: .work,
                contextText: "Handwriting Practice",
                color: .orange,
                associatedID: nil,
                tags: [
                    TagHelper.createTag(name: "Academic", color: .blue),
                    TagHelper.createTag(name: "Behavioral", color: .orange)
                ],
                includeInReport: true,
                needsFollowUp: true,
                imagePath: nil,
                reportedBy: nil,
                reporterName: nil,
                isPinned: false
            ))

            StudentNoteRowView(item: UnifiedNoteItem(
                id: UUID(),
                date: Date().addingTimeInterval(-172800),
                body: "Parent mentioned that student was very excited about the math lesson.",
                source: .general,
                contextText: "General Note",
                color: .blue,
                associatedID: nil,
                tags: [],
                includeInReport: false,
                needsFollowUp: false,
                imagePath: nil,
                reportedBy: "parent",
                reporterName: "Mom",
                isPinned: false
            ))
        }
    }
}
#endif
