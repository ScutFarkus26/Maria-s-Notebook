// swiftlint:disable file_length
import SwiftUI

// MARK: - Reusable Button Components

/// State pill button showing status with icon and conditional highlighting
struct StatePill: View {
    let title: String
    let systemImage: String
    let tint: Color
    var active: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .foregroundStyle(tint)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(active ? 0.20 : 0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(UIConstants.OpacityConstants.statusBg), lineWidth: 1)
        )
    }
}

/// Full-width button container with plain style
struct FullWidthStatePillButton<Content: View>: View {
    let action: () -> Void
    let content: () -> Content
    
    init(action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.action = action
        self.content = content
    }
    
    var body: some View {
        Button(action: action) {
            content()
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Progress & Mastery State Rows

/// Row of progress state buttons (Just Presented, Previously Presented)
struct ProgressStateRow: View {
    let onJustPresented: () -> Void
    let onPreviouslyPresented: () -> Void
    let isJustPresentedActive: Bool
    let isPreviouslyPresentedActive: Bool
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    var body: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            compactLayout
        } else {
            regularLayout
        }
        #else
        regularLayout
        #endif
    }
    
    private var compactLayout: some View {
        HStack(spacing: 8) {
            FullWidthStatePillButton(action: onJustPresented) {
                StatePill(
                    title: "Just Presented",
                    systemImage: "checkmark.circle.fill",
                    tint: .green,
                    active: isJustPresentedActive
                )
            }
            
            FullWidthStatePillButton(action: onPreviouslyPresented) {
                StatePill(
                    title: "Previously",
                    systemImage: "clock.badge.checkmark",
                    tint: .green,
                    active: isPreviouslyPresentedActive
                )
            }
        }
    }
    
    private var regularLayout: some View {
        HStack(spacing: 12) {
            FullWidthStatePillButton(action: onJustPresented) {
                StatePill(
                    title: "Just Presented",
                    systemImage: "checkmark.circle.fill",
                    tint: .green,
                    active: isJustPresentedActive
                )
            }
            
            FullWidthStatePillButton(action: onPreviouslyPresented) {
                StatePill(
                    title: "Previously Presented",
                    systemImage: "clock.badge.checkmark",
                    tint: .green,
                    active: isPreviouslyPresentedActive
                )
            }
        }
    }
}

/// Mastery status row with Presented/Practicing/Mastered options
struct ProficiencyStateRow: View {
    @Binding var proficiencyState: LessonPresentationState
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "star.circle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))
                Text("Mastery Status")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }
            
            // Buttons
            #if os(iOS)
            if horizontalSizeClass == .compact {
                compactButtons
            } else {
                regularButtons
            }
            #else
            regularButtons
            #endif
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(UIConstants.OpacityConstants.subtle), lineWidth: 1)
        )
    }
    
    private var compactButtons: some View {
        VStack(spacing: 8) {
            FullWidthStatePillButton(action: { proficiencyState = .presented }, content: {
                StatePill(
                    title: "Presented",
                    systemImage: "eye.fill",
                    tint: .blue,
                    active: proficiencyState == .presented
                )
            })

            FullWidthStatePillButton(action: { proficiencyState = .practicing }, content: {
                StatePill(
                    title: "Practicing",
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: .purple,
                    active: proficiencyState == .practicing
                )
            })

            FullWidthStatePillButton(action: { proficiencyState = .proficient }, content: {
                StatePill(
                    title: "Mastered",
                    systemImage: "checkmark.seal.fill",
                    tint: .green,
                    active: proficiencyState == .proficient
                )
            })
        }
    }
    
    private var regularButtons: some View {
        HStack(spacing: 12) {
            Button { proficiencyState = .presented } label: {
                StatePill(
                    title: "Presented",
                    systemImage: "eye.fill",
                    tint: .blue,
                    active: proficiencyState == .presented
                )
            }
            .buttonStyle(.plain)
            
            Button { proficiencyState = .practicing } label: {
                StatePill(
                    title: "Practicing",
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: .purple,
                    active: proficiencyState == .practicing
                )
            }
            .buttonStyle(.plain)
            
            Button { proficiencyState = .proficient } label: {
                StatePill(
                    title: "Mastered",
                    systemImage: "checkmark.seal.fill",
                    tint: .green,
                    active: proficiencyState == .proficient
                )
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
    }
}

// MARK: - Bottom Bar

/// Bottom action bar with Delete, Cancel, and Save buttons
struct PresentationBottomBar: View {
    let onDelete: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void
    let isSaveDisabled: Bool
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Group {
                #if os(iOS)
                if horizontalSizeClass == .compact {
                    compactLayout
                } else {
                    regularLayout
                }
                #else
                regularLayout
                #endif
            }
            .background(.bar)
        }
    }
    
    private var compactLayout: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .frame(maxWidth: .infinity)
                
                Button("Cancel", action: onCancel)
                    .frame(maxWidth: .infinity)
            }
            
            Button("Save", action: onSave)
                .bold()
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(isSaveDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var regularLayout: some View {
        HStack {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            
            Spacer()
            
            Button("Cancel", action: onCancel)
            
            Button("Save", action: onSave)
                .bold()
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaveDisabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Workflow Header Components

/// Three-panel workflow header with back button, title, and action buttons
struct WorkflowHeaderBar: View {
    let lessonTitle: String
    let onBack: () -> Void
    let onComplete: () -> Void
    let canComplete: Bool
    #if os(macOS)
    let onPopOut: (() -> Void)?
    #endif
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("\(lessonTitle) Presentation Workflow")
                    .font(AppTheme.ScaledFont.titleMedium)
                
                Spacer()
                
                #if os(macOS)
                if let onPopOut {
                    Button(action: onPopOut) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.square")
                            Text("Pop Out")
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Open in independent window")
                }
                #endif
                
                Button("Complete & Save", action: onComplete)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canComplete)
            }
            .padding()
            .background(.bar)
            
            Divider()
        }
    }
}

/// Planning panel header for three-column layout
struct PlanningPanelHeader: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Planning")
                    .font(AppTheme.ScaledFont.titleSmall)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.bar)
            
            Divider()
        }
    }
}

// MARK: - Section Content Helpers

/// Shared planning content sections layout
struct PlanningContentSections<
    LessonHeader: View, LessonPicker: View,
    StudentPills: View, InboxStatus: View, Notes: View
>: View {
    let horizontalPadding: CGFloat
    let lessonHeader: () -> LessonHeader
    let lessonPicker: () -> LessonPicker
    let studentPills: () -> StudentPills
    let inboxStatus: () -> InboxStatus
    let notes: () -> Notes
    
    init(
        horizontalPadding: CGFloat = 32,
        @ViewBuilder lessonHeader: @escaping () -> LessonHeader,
        @ViewBuilder lessonPicker: @escaping () -> LessonPicker,
        @ViewBuilder studentPills: @escaping () -> StudentPills,
        @ViewBuilder inboxStatus: @escaping () -> InboxStatus,
        @ViewBuilder notes: @escaping () -> Notes
    ) {
        self.horizontalPadding = horizontalPadding
        self.lessonHeader = lessonHeader
        self.lessonPicker = lessonPicker
        self.studentPills = studentPills
        self.inboxStatus = inboxStatus
        self.notes = notes
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. Lesson Title & Tags Header
            lessonHeader()
                .padding(.horizontal, horizontalPadding)
                .padding(.top, horizontalPadding)
            
            // 2. Lesson Picker
            lessonPicker()
            
            // 3. Student Pills Block
            studentPills()
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 20)
            
            Divider()
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 20)
            
            // 4. Inbox/Scheduling Status Row
            inboxStatus()
                .padding(.horizontal, horizontalPadding)
            
            Divider()
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 20)
            
            // 5. Notes Section
            notes()
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 32)
        }
    }
}
