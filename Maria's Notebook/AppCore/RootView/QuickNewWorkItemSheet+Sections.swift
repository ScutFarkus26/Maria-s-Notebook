// QuickNewWorkItemSheet+Sections.swift
// CDLesson, student, and details section builders for QuickNewWorkItemSheet.

import SwiftUI

extension QuickNewWorkItemSheet {

    // MARK: - CDLesson Section

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    func lessonSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lesson")
                .font(.headline)

            // Search field with popover
            TextField("Search lessons...", text: $lessonSearchText)
                .textFieldStyle(.roundedBorder)
                .focused($lessonFieldFocused)
                .onChange(of: lessonSearchText) { _, newValue in
                    if !newValue.trimmed().isEmpty {
                        showingLessonPopover = true
                    }
                }
                .onSubmit {
                    // If user typed an exact lesson name, select it
                    let trimmed = lessonSearchText.trimmed()
                    let isMatch: (CDLesson) -> Bool = {
                        $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
                    }
                    if let match = filteredLessons.first(where: isMatch) {
                        selectLesson(match)
                    }
                }
                .onTapGesture {
                    showingLessonPopover = true
                }
                .popover(isPresented: $showingLessonPopover, arrowEdge: .bottom) {
                    lessonPopoverContent()
                }

            // Selected lesson display
            if let lesson = selectedLesson {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lesson.name)
                            .font(.subheadline.weight(.bold))
                        if !lesson.subject.isEmpty {
                            Text(lesson.subject)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        selectedLessonID = nil
                        lessonSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(AppTheme.Spacing.compact)
                .background(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                .cornerRadius(UIConstants.CornerRadius.medium)
            } else {
                Text("Choose a lesson to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Sample work picker (when lesson has templates)
            if let lesson = selectedLesson, !lesson.orderedSampleWorks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Template")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)

                    Picker("Sample Work", selection: $selectedSampleWorkID) {
                        Text("None").tag(UUID?.none)
                        ForEach(lesson.orderedSampleWorks, id: \.id) { sw in
                            HStack {
                                Text(sw.title)
                                if sw.stepCount > 0 {
                                    Text("(\(sw.stepCount) steps)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(sw.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .onChange(of: selectedSampleWorkID) { _, newID in
                    guard let id = newID,
                          let lesson = selectedLesson,
                          let sw = lesson.orderedSampleWorks.first(where: { $0.id == id }) else { return }
                    workTitle = sw.title
                    if let kind = sw.workKind { workKind = kind }
                }
            }
        }
    }

    @ViewBuilder
    func lessonPopoverContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            List(filteredLessons.prefix(15), id: \.id) { lesson in
                Button {
                    selectLesson(lesson)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lesson.name)
                                .foregroundStyle(.primary)
                            if !lesson.subject.isEmpty {
                                Text("\(lesson.subject) • \(lesson.group)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selectedLessonID == lesson.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            #if os(macOS)
            .focusable(false)
            #endif
        }
        .padding(AppTheme.Spacing.small)
        #if os(macOS)
        .frame(minWidth: UIConstants.SheetSize.compact.width, minHeight: 300)
        #else
        .frame(minHeight: 300)
        #endif
    }

    func selectLesson(_ lesson: CDLesson) {
        selectedLessonID = lesson.id
        lessonSearchText = lesson.name
        showingLessonPopover = false
        lessonFieldFocused = false
        selectedSampleWorkID = nil

        // Auto-set work title if empty
        if workTitle.isEmpty {
            workTitle = lesson.name
        }
    }

    // MARK: - CDStudent Section

    func removeStudent(id: UUID) {
        _ = adaptiveWithAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            selectedStudentIDs.remove(id)
        }
    }

    @ViewBuilder
    func studentChip(for student: CDStudent) -> some View {
        HStack(spacing: 4) {
            Text(StudentFormatter.displayName(for: student))
                .font(AppTheme.ScaledFont.bodySemibold)
                .padding(.horizontal, AppTheme.Spacing.compact)
                .padding(.vertical, AppTheme.Spacing.verySmall)
                .background(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
                .foregroundStyle(Color.accentColor)
                .clipShape(Capsule())

            Button {
                if let studentID = student.id { removeStudent(id: studentID) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    func studentSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Student")
                .font(.headline)

            HStack(alignment: .center, spacing: 8) {
                // Selected students as chips
                if !selectedStudents.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedStudents, id: \.id) { student in
                                studentChip(for: student)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Add student button
                Button {
                    showingStudentPopover = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingStudentPopover, arrowEdge: .bottom) {
                    StudentPickerPopover(
                        students: allStudents,
                        selectedIDs: $selectedStudentIDs,
                        onDone: { showingStudentPopover = false }
                    )
                }
            }
            .adaptiveAnimation(.spring(response: 0.25, dampingFraction: 0.85), value: selectedStudentIDs)

            if selectedStudentIDs.isEmpty {
                Text("Add at least one student.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Details Section

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    func detailsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            TextField("Title (optional)", text: $workTitle)
                .textFieldStyle(.roundedBorder)

            // Work Kind picker as segmented buttons
            HStack(spacing: 0) {
                kindButton(.practiceLesson, "Practice")
                kindButton(.followUpAssignment, "Follow-Up")
                kindButton(.research, "Project")
                kindButton(.report, "Report")
            }
            .background(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                    .stroke(Color.primary.opacity(UIConstants.OpacityConstants.light))
            )

            // Due date toggle and picker
            Toggle("Set due date", isOn: $hasDueDate)
                .onChange(of: hasDueDate) { _, newValue in
                    if newValue {
                        if dueDate == nil {
                            dueDate = AppCalendar.startOfDay(Date())
                        }
                    } else {
                        dueDate = nil
                    }
                }

            if hasDueDate {
                DatePicker("Due date", selection: Binding(
                    get: { dueDate ?? AppCalendar.startOfDay(Date()) },
                    set: { dueDate = $0 }
                ), displayedComponents: .date)
            }

            Divider()
                .padding(.vertical, 8)

            // Check-in toggle and controls
            Toggle("Schedule check-in", isOn: $hasCheckIn)
                .onChange(of: hasCheckIn) { _, newValue in
                    if newValue {
                        checkInDate = AppCalendar.startOfDay(Date())
                    }
                }

            if hasCheckIn {
                HStack(spacing: 12) {
                    DatePicker("Check-in date", selection: $checkInDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)

                    Menu {
                        ForEach(CheckInReason.allCases) { reason in
                            Button {
                                checkInReason = reason
                            } label: {
                                HStack {
                                    Image(systemName: legacyReasonIcon(reason))
                                    Text(legacyReasonLabel(reason))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: legacyReasonIcon(checkInReason))
                                .font(.system(size: 12, weight: .medium))
                            Text(legacyReasonLabel(checkInReason))
                                .font(AppTheme.ScaledFont.captionSemibold)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, AppTheme.Spacing.compact)
                        .padding(.vertical, AppTheme.Spacing.small)
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                                .fill(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
                        )
                    }
                }
            }

            // Check-in style picker (only shown when multiple students selected)
            if selectedStudentIDs.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Check-In Style")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(CheckInStyle.allCases) { style in
                            SelectablePillButton(
                                item: style,
                                isSelected: checkInStyle == style,
                                color: style.color,
                                icon: style.iconName,
                                label: style.displayName
                            ) {
                                adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    checkInStyle = style
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func kindButton(_ kind: WorkKind, _ label: String) -> some View {
        Button(label) {
            workKind = kind
        }
        .padding(.horizontal, AppTheme.Spacing.compact)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(workKind == kind ? Color.accentColor.opacity(UIConstants.OpacityConstants.light) : Color.clear)
        .foregroundStyle(workKind == kind ? Color.accentColor : .primary)
        .font(.subheadline)
    }
}
