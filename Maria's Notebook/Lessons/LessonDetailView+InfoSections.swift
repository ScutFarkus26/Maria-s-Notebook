import SwiftUI

// MARK: - Info Display Sections

extension LessonDetailView {
    var infoSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            infoRow(
                icon: SFSymbol.Education.bookClosed, title: "Name",
                value: lesson.name.isEmpty ? "Untitled Lesson" : lesson.name
            )
            infoRow(
                icon: SFSymbol.Education.graduationcap, title: "Subject",
                value: lesson.subject.isEmpty ? "\u{2014}" : lesson.subject
            )
            infoRow(
                icon: SFSymbol.List.squareGrid, title: "Group",
                value: lesson.group.isEmpty ? "\u{2014}" : lesson.group
            )
            infoRow(
                icon: "text.bubble", title: "Subheading",
                value: lesson.subheading.isEmpty ? "\u{2014}" : lesson.subheading
            )
            infoRow(
                icon: "square.stack.3d.up", title: "Source",
                value: lesson.source.label
            )
            if lesson.source == .personal {
                infoRow(
                    icon: SFSymbol.People.person, title: "Personal Type",
                    value: lesson.personalKind?.label ?? "Personal"
                )
            }
            if !lesson.ageRange.isEmpty {
                infoRow(icon: "person.2", title: "Age Range", value: lesson.ageRange)
            }

            // Purpose
            if !lesson.purpose.trimmed().isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                    HStack(spacing: AppTheme.Spacing.small + 2) {
                        Image(systemName: "target")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Purpose")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                            .foregroundStyle(.secondary)
                    }
                    Text(lesson.purpose)
                        .font(AppTheme.ScaledFont.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, AppTheme.Spacing.verySmall)
            }

            // Materials
            if !lesson.materialsItems.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                    HStack(spacing: AppTheme.Spacing.small + 2) {
                        Image(systemName: "tray.full")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Materials")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                        ForEach(lesson.materialsItems, id: \.self) { item in
                            HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                                Text("\u{2022}").font(AppTheme.ScaledFont.body)
                                Text(item)
                                    .font(AppTheme.ScaledFont.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.top, AppTheme.Spacing.verySmall)
            }

            // Write Up (Presentation Notes)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                HStack(spacing: AppTheme.Spacing.small + 2) {
                    Image(systemName: SFSymbol.Document.docText)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("Presentation Notes")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(.secondary)
                }
                if lesson.writeUp.trimmed().isEmpty {
                    Text("No notes yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(lesson.writeUp)
                        .font(AppTheme.ScaledFont.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, AppTheme.Spacing.verySmall)

            // Teacher Notes
            if !lesson.teacherNotes.trimmed().isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                    HStack(spacing: AppTheme.Spacing.small + 2) {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Teacher Notes")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                            .foregroundStyle(.secondary)
                    }
                    Text(lesson.teacherNotes)
                        .font(AppTheme.ScaledFont.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, AppTheme.Spacing.verySmall)
            }

            // Exercises
            if !lesson.sortedExercises.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        ForEach(lesson.sortedExercises) { exercise in
                            LessonExerciseRow(exercise: exercise)
                        }
                    }
                    .padding(.top, AppTheme.Spacing.xsmall)
                } label: {
                    HStack(spacing: AppTheme.Spacing.small + 2) {
                        Image(systemName: "list.number")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Exercises (\(lesson.sortedExercises.count))")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, AppTheme.Spacing.verySmall)
            }

            // Suggested Follow-Up Work
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                HStack(spacing: AppTheme.Spacing.small + 2) {
                    Image(systemName: SFSymbol.Action.checkmarkCircle)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("Suggested Follow-Up Work")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(.secondary)
                }
                if lesson.suggestedFollowUpWorkItems.isEmpty {
                    Text("No suggestions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                        ForEach(lesson.suggestedFollowUpWorkItems, id: \.self) { item in
                            HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                                Text("\u{2022}").font(AppTheme.ScaledFont.body)
                                Text(item)
                                    .font(AppTheme.ScaledFont.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .padding(.top, AppTheme.Spacing.verySmall)

            // Prerequisites
            if !lesson.prerequisiteLessonUUIDs.isEmpty {
                LessonRelationshipsSection(
                    title: "Prerequisites",
                    icon: "arrow.backward.circle",
                    lessonIDs: lesson.prerequisiteLessonUUIDs,
                    modelContext: modelContext
                )
            }

            // Related Lessons
            if !lesson.relatedLessonUUIDs.isEmpty {
                LessonRelationshipsSection(
                    title: "Related Lessons",
                    icon: "link",
                    lessonIDs: lesson.relatedLessonUUIDs,
                    modelContext: modelContext
                )
            }

            if let url = resolvedPagesURL {
                HStack { Spacer() }
                OpenInPagesButton(title: "Open in Pages") { openInPages(url) }
                    .padding(.vertical, AppTheme.Spacing.small)
                HStack { Spacer() }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.small)
    }

    func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: AppTheme.Spacing.small + 2) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(AppTheme.ScaledFont.titleSmall)
        }
    }
}
