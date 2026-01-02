//
//  StudentNoteRowView.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 12/27/25.
//


import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct StudentNoteRowView: View {
    let item: UnifiedNoteItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 1. Leading Icon
            ZStack {
                Circle()
                    .fill(item.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: iconName(for: item.source))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(item.color)
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
                
                // Category badge
                categoryBadge(item.category)

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
        if let image = PhotoStorageService.loadImage(filename: imagePath) {
            #if os(macOS)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 300, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 8)
            #else
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 300, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 8)
            #endif
        }
    }

    private func iconName(for source: UnifiedNoteItem.Source) -> String {
        switch source {
        case .general: return "person.bubble.fill"
        case .lesson:  return "book.closed.fill"
        case .work:    return "doc.text.fill"
        case .meeting: return "person.2.fill"
        case .presentation: return "presentation.fill"
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
    
    @ViewBuilder
    private func categoryBadge(_ category: NoteCategory) -> some View {
        let color = categoryColor(for: category)
        Text(category.rawValue.capitalized)
            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
    }
    
    private func categoryColor(for category: NoteCategory) -> Color {
        switch category {
        case .academic:
            return .blue
        case .behavioral:
            return .orange
        case .social:
            return .green
        case .emotional:
            return .pink
        case .health:
            return .red
        case .general:
            return .gray
        }
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
                category: .academic,
                includeInReport: false,
                imagePath: nil,
                reportedBy: nil,
                reporterName: nil
            ))
            
            StudentNoteRowView(item: UnifiedNoteItem(
                id: UUID(),
                date: Date().addingTimeInterval(-86400),
                body: "Needs to focus more on handwriting clarity during follow-up work.",
                source: .work,
                contextText: "Handwriting Practice",
                color: .orange,
                associatedID: nil,
                category: .academic,
                includeInReport: true,
                imagePath: nil,
                reportedBy: nil,
                reporterName: nil
            ))
            
            StudentNoteRowView(item: UnifiedNoteItem(
                id: UUID(),
                date: Date().addingTimeInterval(-172800),
                body: "Parent mentioned that student was very excited about the math lesson.",
                source: .general,
                contextText: "General Note",
                color: .blue,
                associatedID: nil,
                category: .general,
                includeInReport: false,
                imagePath: nil,
                reportedBy: "parent",
                reporterName: "Mom"
            ))
        }
    }
}
#endif