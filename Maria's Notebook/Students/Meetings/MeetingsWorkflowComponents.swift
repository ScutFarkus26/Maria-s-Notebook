import SwiftUI
import SwiftData

// MARK: - Queue Sidebar (Separate View)

struct MeetingsQueueSidebar: View {
    let studentsNeedingMeeting: [Student]
    let studentsCompleted: [Student]
    @Binding var selectedStudentID: UUID?
    @Binding var searchText: String
    @Binding var showCompletedThisWeek: Bool
    @Binding var daysSinceThreshold: Int
    @Binding var selectedAgeRanges: Set<AgeRange>
    let lastMeetingFor: (Student) -> StudentMeeting?
    let onMove: (IndexSet, Int) -> Void

    var body: some View {
        List(selection: $selectedStudentID) {
            // Threshold picker and age filter at top
            Section {
                MeetingThresholdPicker(days: $daysSinceThreshold, showCompleted: $showCompletedThisWeek)
                AgeFilterPicker(selectedAgeRanges: $selectedAgeRanges)
            }

            Section("Needs Meeting (\(studentsNeedingMeeting.count))") {
                ForEach(studentsNeedingMeeting) { student in
                    StudentQueueRow(
                        student: student,
                        lastMeeting: lastMeetingFor(student),
                        isSelected: selectedStudentID == student.id,
                        showCheckmark: false
                    )
                    .tag(student.id)
                }
                .onMove(perform: searchText.isEmpty ? onMove : nil)
            }

            if showCompletedThisWeek {
                Section("Met Recently (\(studentsCompleted.count))") {
                    ForEach(studentsCompleted) { student in
                        StudentQueueRow(
                            student: student,
                            lastMeeting: lastMeetingFor(student),
                            isSelected: selectedStudentID == student.id,
                            showCheckmark: true
                        )
                        .tag(student.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search students")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 220)
        #endif
    }
}

// MARK: - Meeting Threshold Picker

struct MeetingThresholdPicker: View {
    @Binding var days: Int
    @Binding var showCompleted: Bool
    @State private var isExpanded = false

    private let presets = [3, 5, 7, 14, 21, 30]

    var body: some View {
        VStack(spacing: 8) {
            // Top row: threshold pill + show completed toggle
            HStack(spacing: 8) {
                // Tappable pill showing current value
                Button {
                    adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption)

                        Text("Last \(days)d")
                            .font(.subheadline.weight(.medium))

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.12))
                    )
                    .foregroundStyle(.accent)
                }
                .buttonStyle(.plain)

                // Show completed toggle
                Button {
                    adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                        showCompleted.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.caption)

                        Text("Done")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(showCompleted ? Color.green.opacity(0.15) : Color.primary.opacity(0.06))
                    )
                    .foregroundStyle(showCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Expanded picker
            if isExpanded {
                VStack(spacing: 8) {
                    // Quick presets
                    HStack(spacing: 6) {
                        ForEach(presets, id: \.self) { preset in
                            Button {
                                adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                                    days = preset
                                }
                            } label: {
                                Text("\(preset)")
                                    .font(.caption.weight(days == preset ? .semibold : .regular))
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(days == preset ? Color.accentColor : Color.primary.opacity(0.06))
                                    )
                                    .foregroundStyle(days == preset ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Fine-tune stepper
                    HStack(spacing: 12) {
                        Button {
                            if days > 1 { days -= 1 }
                        } label: {
                            Image(systemName: "minus")
                                .font(.caption.weight(.medium))
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .disabled(days <= 1)

                        Text("\(days) day\(days == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 60)

                        Button {
                            if days < 90 { days += 1 }
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption.weight(.medium))
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .disabled(days >= 90)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Student Queue Row

struct StudentQueueRow: View {
    let student: Student
    let lastMeeting: StudentMeeting?
    var isSelected: Bool = false
    var showCheckmark: Bool = false

    @Environment(\.modelContext) private var modelContext

    private var daysSinceLastMeeting: Int? {
        guard let lastMeeting = lastMeeting else { return nil }
        return Calendar.current.dateComponents([.day], from: lastMeeting.date, to: Date()).day
    }

    private var isAbsentToday: Bool {
        modelContext.attendanceStatus(for: student.id, on: Date()) == .absent
    }

    var body: some View {
        HStack(spacing: 10) {
            StudentAvatarView(student: student, size: 36)
                .overlay(
                    Circle()
                        .stroke(isAbsentToday ? Color.red : Color.clear, lineWidth: 1.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(StudentFormatter.displayName(for: student))
                    .font(.subheadline.weight(.medium))

                if let days = daysSinceLastMeeting {
                    Text("\(days) days ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No prior meetings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if showCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Age Filter Picker

struct AgeFilterPicker: View {
    @Binding var selectedAgeRanges: Set<AgeRange>

    private var displayText: String {
        if selectedAgeRanges.isEmpty {
            return "All Ages"
        } else if selectedAgeRanges.count == 1, let first = selectedAgeRanges.first {
            return first.rawValue
        } else {
            return "\(selectedAgeRanges.count) Ages"
        }
    }

    var body: some View {
        Menu {
            Button("All Ages") {
                selectedAgeRanges.removeAll()
            }

            Divider()

            ForEach(AgeRange.allCases) { range in
                Button(action: {
                    if selectedAgeRanges.contains(range) {
                        selectedAgeRanges.remove(range)
                    } else {
                        selectedAgeRanges.insert(range)
                    }
                }, label: {
                    HStack {
                        if selectedAgeRanges.contains(range) {
                            Image(systemName: "checkmark")
                        }
                        Text(range.rawValue)
                    }
                })
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption)

                Text(displayText)
                    .font(.subheadline.weight(.medium))

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(selectedAgeRanges.isEmpty ? Color.primary.opacity(0.06) : Color.accentColor.opacity(0.12))
            )
            .foregroundStyle(selectedAgeRanges.isEmpty ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}
