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
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.contextText)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Text(formattedDate(item.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(item.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true) // Ensures text wraps properly
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle()) // Ensures the whole row is tappable
    }

    // MARK: - Helpers

    private func iconName(for source: UnifiedNoteItem.Source) -> String {
        switch source {
        case .general: return "person.bubble.fill"
        case .lesson:  return "book.closed.fill"
        case .work:    return "doc.text.fill"
        case .meeting: return "person.2.fill"
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
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
                associatedID: nil
            ))
            
            StudentNoteRowView(item: UnifiedNoteItem(
                id: UUID(),
                date: Date().addingTimeInterval(-86400),
                body: "Needs to focus more on handwriting clarity during follow-up work.",
                source: .work,
                contextText: "Handwriting Practice",
                color: .orange,
                associatedID: nil
            ))
        }
    }
}
#endif