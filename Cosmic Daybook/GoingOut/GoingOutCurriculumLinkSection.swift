// GoingOutCurriculumLinkSection.swift
// Shows linked curriculum lessons with area colors.

import SwiftUI
import CoreData

struct GoingOutCurriculumLinkSection: View {
    @ObservedObject var goingOut: CDGoingOut
    @Environment(\.managedObjectContext) private var modelContext
    @State private var showingLessonPicker = false

    private var linkedLessons: [CDLesson] {
        let uuids = goingOut.curriculumLinkUUIDs
        guard !uuids.isEmpty else { return [] }

        // Fetch only the linked lessons; this used to load the whole Lesson
        // table and filter it in Swift, twice per body pass.
        let request: NSFetchRequest<CDLesson> = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id IN %@", uuids)
        return modelContext.safeFetch(request)
    }

    var body: some View {
        let linkedLessons = self.linkedLessons
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Curriculum Links")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    showingLessonPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption2)
                        Text("Link")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            if linkedLessons.isEmpty {
                Text("No curriculum links yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(linkedLessons, id: \.objectID) { lesson in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AppColors.color(forArea: lesson.area))
                                .frame(width: 6, height: 6)
                            Text(lesson.name)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Button {
                                removeLink(lesson)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .capsuleFill(
                            AppColors.color(forArea: lesson.area).opacity(UIConstants.OpacityConstants.light),
                            style: .continuous
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showingLessonPicker) {
            lessonPickerSheet
        }
    }

    // MARK: - CDLesson Picker

    private var lessonPickerSheet: some View {
        NavigationStack {
            LessonLinkPicker(selection: linkedIDs)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingLessonPicker = false }
                    }
                }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    /// The linked lessons as the picker ticks them. A change is saved at once,
    /// keeping the links in the order they were made.
    private var linkedIDs: Binding<Set<UUID>> {
        Binding(
            get: { Set(goingOut.curriculumLinkUUIDs) },
            set: { newValue in
                var current = goingOut.curriculumLinkUUIDs.filter(newValue.contains)
                current += newValue.subtracting(current).sorted { $0.uuidString < $1.uuidString }
                goingOut.curriculumLinkUUIDs = current
                goingOut.modifiedAt = Date()
                modelContext.safeSave()
            }
        )
    }

    private func removeLink(_ lesson: CDLesson) {
        guard let lessonID = lesson.id else { return }
        var current = goingOut.curriculumLinkUUIDs
        current.removeAll { $0 == lessonID }
        goingOut.curriculumLinkUUIDs = current
        goingOut.modifiedAt = Date()
        modelContext.safeSave()
    }
}
