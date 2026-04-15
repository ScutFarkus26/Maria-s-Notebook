// MeetingDetailSheet.swift
// Full meeting detail presented as a sheet from Recent Meetings

import SwiftUI
import CoreData

struct MeetingDetailSheet: View {
    let meeting: CDStudentMeeting
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !meeting.reflection.trimmed().isEmpty {
                        DetailLine(title: "Reflection", text: meeting.reflection)
                    }

                    if !meeting.focus.trimmed().isEmpty {
                        DetailLine(title: "Focus", text: meeting.focus)
                    }

                    if !meeting.requests.trimmed().isEmpty {
                        DetailLine(title: "Requests", text: meeting.requests)
                    }

                    if !meeting.guideNotes.trimmed().isEmpty {
                        DetailLine(title: "Guide Notes", text: meeting.guideNotes)
                    }

                    // Work Reviewed section
                    workReviewsSection

                    // Focus Items section
                    focusItemsSection

                    if meeting.reflection.trimmed().isEmpty
                        && meeting.focus.trimmed().isEmpty
                        && meeting.requests.trimmed().isEmpty
                        && meeting.guideNotes.trimmed().isEmpty
                        && workReviews.isEmpty
                        && focusItems.isEmpty {
                        Text("No notes recorded")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(
                (meeting.date ?? Date()).formatted(date: .long, time: .omitted)
            )
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Work Reviews

    private var workReviews: [CDMeetingWorkReview] {
        guard let meetingID = meeting.id else { return [] }
        return MeetingReviewService.fetchReviews(meetingID: meetingID, context: viewContext)
    }

    @ViewBuilder
    private var workReviewsSection: some View {
        let reviews = workReviews
        if !reviews.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Work Reviewed", systemImage: "tray.full")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.top, 4)

                ForEach(reviews, id: \.id) { review in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.success)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(workTitle(for: review.workID))
                                .font(.footnote.weight(.medium))

                            if !review.noteText.trimmed().isEmpty {
                                Text(review.noteText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func workTitle(for workID: String) -> String {
        let request = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
        request.predicate = NSPredicate(format: "id == %@", (UUID(uuidString: workID) ?? UUID()) as CVarArg)
        request.fetchLimit = 1
        if let work = try? viewContext.fetch(request).first {
            let title = work.title.trimmed()
            return title.isEmpty ? "Work Item" : title
        }
        return "Work Item"
    }

    // MARK: - Focus Items

    private var focusItems: [CDStudentFocusItem] {
        guard let meetingID = meeting.id else { return [] }
        return FocusItemService.fetchForMeeting(meetingID: meetingID, context: viewContext)
    }

    @ViewBuilder
    private var focusItemsSection: some View {
        let items = focusItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Focus Items", systemImage: "target")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.top, 4)

                ForEach(items, id: \.id) { item in
                    HStack(spacing: 8) {
                        if item.createdInMeetingID == meeting.id?.uuidString {
                            Text("New")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.accent))
                        }

                        if item.isResolved {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(AppColors.success)
                        } else if item.isDropped {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(item.text)
                            .font(.footnote)
                            .strikethrough(item.isResolved || item.isDropped)
                            .foregroundStyle(item.isResolved || item.isDropped ? .secondary : .primary)
                    }
                }
            }
        }
    }
}
