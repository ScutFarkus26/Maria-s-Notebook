import SwiftUI
import CoreData

// MARK: - Summary Section
struct PresentationSummarySection: View {
    let lessonName: String
    let subject: String
    let subjectColor: Color
    let students: [CDStudent]
    let canMoveStudents: Bool
    let onMoveStudents: () -> Void
    let onAddRemoveStudents: () -> Void
    let onRemoveStudent: (CDStudent) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Title and subject badge
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(lessonName)
                    .font(AppTheme.ScaledFont.titleLarge)
                    .multilineTextAlignment(.center)
                
                if !subject.isEmpty {
                    Text(subject)
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(subjectColor)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(subjectColor.opacity(UIConstants.OpacityConstants.accent))
                        )
                }
            }
            .frame(maxWidth: .infinity)
            
            // CDStudent chips and action buttons
            ViewThatFits(in: .horizontal) {
                // Try single line layout
                HStack(alignment: .center, spacing: 8) {
                    studentChipsScrollView
                    Spacer(minLength: 0)
                    actionButtons
                }
                
                // Fall back to wrapped layout
                VStack(spacing: 8) {
                    studentChipsScrollView
                    HStack(spacing: 8) {
                        Spacer()
                        actionButtons
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var studentChipsScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(students, id: \.id) { student in
                    StudentChip(
                        student: student,
                        subjectColor: subjectColor,
                        onRemove: { onRemoveStudent(student) }
                    )
                }
            }
        }
    }
    
    private var actionButtons: some View {
        Group {
            if canMoveStudents {
                Button {
                    onMoveStudents()
                } label: {
                    Label("Move Students", systemImage: "arrow.right.square")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
            }
            
            Button {
                onAddRemoveStudents()
            } label: {
                Label("Add/Remove Students", systemImage: "person.2.badge.plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Schedule Section
struct PresentationScheduleSection: View {
    let statusText: String
    let isScheduled: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                
                Text("Scheduled For")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                
                Spacer(minLength: 0)
                
                Text(statusText)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(isScheduled ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Given/Presented Section
struct PresentationPresentedSection: View {
    @Binding var isPresented: Bool
    @Binding var givenAt: Date?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.clock")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                
                Text("Presented")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }
            
            Toggle("Presented", isOn: $isPresented)
            
            Toggle("Add date", isOn: Binding(
                get: { givenAt != nil },
                set: { newValue in
                    givenAt = newValue ? (givenAt ?? Date()) : nil
                }
            ))
            
            if givenAt != nil {
                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { givenAt ?? Date() },
                        set: { givenAt = $0 }
                    ),
                    displayedComponents: [.date]
                )
                #if os(macOS)
                .datePickerStyle(.field)
                #else
                .datePickerStyle(.compact)
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Next CDLesson Section
struct PresentationNextLessonSection: View {
    let isPresented: Bool
    let nextLesson: CDLesson?
    let canPlanNext: Bool
    let onPlanNext: () -> Void
    
    var body: some View {
        Group {
            if isPresented {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.plus")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        
                        Text("Next CDLesson in Group")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let next = nextLesson {
                        Text(next.name)
                            .font(AppTheme.ScaledFont.bodySemibold)
                        
                        Button {
                            onPlanNext()
                        } label: {
                            Label("Plan Next CDLesson in Group", systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canPlanNext)
                    } else {
                        Text("No next lesson available")
                            .font(AppTheme.ScaledFont.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Flags Section
struct PresentationFlagsSection: View {
    @Binding var needsPractice: Bool
    @Binding var needsAnotherPresentation: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flag")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                
                Text("Flags")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }
            
            Toggle("Needs Practice", isOn: $needsPractice)
            Toggle("Needs Another Presentation", isOn: $needsAnotherPresentation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Follow Up Section
struct PresentationFollowUpSection: View {
    @Binding var followUpWork: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                
                Text("Follow Up Work")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }
            
            TextField("Follow Up Work", text: $followUpWork)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Notes Section
struct PresentationNotesSection: View {
    @Binding var notes: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.plaintext")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                
                Text("Notes")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }
            
            TextEditor(text: $notes)
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
