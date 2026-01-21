// RootViewComponents.swift
// Supporting components for RootView - extracted for maintainability

import SwiftUI
import SwiftData

// MARK: - Pie Menu Action

enum PieMenuAction: CaseIterable {
    case newPresentation
    case newWorkItem

    var icon: String {
        switch self {
        case .newPresentation: return "person.crop.rectangle.stack"
        case .newWorkItem: return "tray.and.arrow.down"
        }
    }

    var label: String {
        switch self {
        case .newPresentation: return "Present"
        case .newWorkItem: return "Work"
        }
    }

    var color: Color {
        switch self {
        case .newPresentation: return .blue
        case .newWorkItem: return .orange
        }
    }
}

// MARK: - Pie Menu Segment

struct PieMenuSegment: View {
    let action: PieMenuAction
    let isTop: Bool
    let isExpanded: Bool
    let isHighlighted: Bool
    let radius: CGFloat

    private let segmentAngle: Double = 180 // Each segment covers 180 degrees (half circle)
    private let innerRadius: CGFloat = 35

    var body: some View {
        ZStack {
            // Segment background
            PieSlice(
                startAngle: .degrees(isTop ? -180 : 0),
                endAngle: .degrees(isTop ? 0 : 180),
                innerRadius: innerRadius,
                outerRadius: radius
            )
            .fill(
                isHighlighted
                    ? action.color.opacity(0.9)
                    : Color.white.opacity(0.15)
            )
            .overlay(
                PieSlice(
                    startAngle: .degrees(isTop ? -180 : 0),
                    endAngle: .degrees(isTop ? 0 : 180),
                    innerRadius: innerRadius,
                    outerRadius: radius
                )
                .strokeBorder(
                    isHighlighted ? action.color : Color.white.opacity(0.3),
                    lineWidth: 1.5
                )
            )

            // Icon only, centered in segment
            Image(systemName: action.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isHighlighted ? .white : .white.opacity(0.9))
                .offset(y: isTop ? -(innerRadius + radius) / 2 : (innerRadius + radius) / 2)
        }
        .scaleEffect(isExpanded ? 1.0 : 0.01)
        .opacity(isExpanded ? 1.0 : 0.0)
    }
}

// MARK: - Pie Slice Shape

struct PieSlice: InsettableShape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let adjustedOuterRadius = outerRadius - insetAmount
        let adjustedInnerRadius = innerRadius + insetAmount

        var path = Path()

        // Start at inner arc
        let innerStart = CGPoint(
            x: center.x + adjustedInnerRadius * cos(CGFloat(startAngle.radians)),
            y: center.y + adjustedInnerRadius * sin(CGFloat(startAngle.radians))
        )
        path.move(to: innerStart)

        // Draw outer arc
        let outerStart = CGPoint(
            x: center.x + adjustedOuterRadius * cos(CGFloat(startAngle.radians)),
            y: center.y + adjustedOuterRadius * sin(CGFloat(startAngle.radians))
        )
        path.addLine(to: outerStart)
        path.addArc(
            center: center,
            radius: adjustedOuterRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )

        // Draw line to inner arc end
        let innerEnd = CGPoint(
            x: center.x + adjustedInnerRadius * cos(CGFloat(endAngle.radians)),
            y: center.y + adjustedInnerRadius * sin(CGFloat(endAngle.radians))
        )
        path.addLine(to: innerEnd)

        // Draw inner arc back
        path.addArc(
            center: center,
            radius: adjustedInnerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )

        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var slice = self
        slice.insetAmount += amount
        return slice
    }
}

// MARK: - Quick Note Glass Button

/// Isolated component to prevent RootView re-renders during drag
struct QuickNoteGlassButton: View {
    @Binding var isShowingSheet: Bool
    @Binding var isShowingPresentationSheet: Bool
    @Binding var isShowingWorkItemSheet: Bool

    @State private var offset: CGSize = .zero
    @State private var isPressed: Bool = false
    @State private var isPieMenuExpanded: Bool = false
    @State private var highlightedAction: PieMenuAction? = nil
    @State private var dragTranslation: CGSize = .zero
    @State private var longPressTask: Task<Void, Never>? = nil

    @AppStorage("QuickNoteButton.offsetX") private var savedOffsetX: Double = 0
    @AppStorage("QuickNoteButton.offsetY") private var savedOffsetY: Double = 0

    private let pieMenuRadius: CGFloat = 95
    private let longPressDuration: UInt64 = 400_000_000 // 0.4 seconds in nanoseconds

    var body: some View {
        // Main button with fixed size
        visualContent
            .scaleEffect(isPressed && !isPieMenuExpanded ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .overlay {
                // Pie menu segments overlay (doesn't affect button layout)
                if isPieMenuExpanded {
                    pieMenuOverlay
                }
            }
        .offset(offset)
        .padding(.trailing, 20)
        #if os(iOS)
        .padding(.bottom, 85)
        #else
        .padding(.bottom, 40)
        #endif
        .gesture(combinedGesture)
        .onAppear {
            self.offset = CGSize(width: savedOffsetX, height: savedOffsetY)
        }
        .onDisappear {
            longPressTask?.cancel()
        }
        .accessibilityLabel("Add quick note")
        .accessibilityHint("Double tap to open note editor, hold to see more options, or drag to reposition")
        .accessibilityAddTraits(.isButton)
    }

    private var pieMenuOverlay: some View {
        ZStack {
            // Top segment - New Presentation
            PieMenuSegment(
                action: .newPresentation,
                isTop: true,
                isExpanded: isPieMenuExpanded,
                isHighlighted: highlightedAction == .newPresentation,
                radius: pieMenuRadius
            )

            // Bottom segment - New Work Item
            PieMenuSegment(
                action: .newWorkItem,
                isTop: false,
                isExpanded: isPieMenuExpanded,
                isHighlighted: highlightedAction == .newWorkItem,
                radius: pieMenuRadius
            )
        }
        .background(
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: pieMenuRadius * 2 + 20, height: pieMenuRadius * 2 + 20)
                .opacity(isPieMenuExpanded ? 1.0 : 0.0)
        )
    }

    private var visualContent: some View {
        Group {
            #if os(iOS)
            Image(systemName: isPieMenuExpanded ? "xmark" : "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .rotationEffect(.degrees(isPieMenuExpanded ? 90 : 0))
            #else
            Image(systemName: isPieMenuExpanded ? "xmark" : "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .rotationEffect(.degrees(isPieMenuExpanded ? 90 : 0))
            #endif
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPieMenuExpanded)
    }

    private var combinedGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Start long press task on first touch
                if longPressTask == nil && !isPieMenuExpanded {
                    isPressed = true
                    startLongPressTask()
                }

                dragTranslation = value.translation
                let distance = hypot(value.translation.width, value.translation.height)

                // Cancel long press if user drags too far
                if distance >= 10 && !isPieMenuExpanded {
                    longPressTask?.cancel()
                    longPressTask = nil
                }

                // If pie menu is expanded, track which segment is highlighted
                if isPieMenuExpanded {
                    updateHighlightedAction(translation: value.translation)
                } else if distance >= 2 && longPressTask == nil {
                    // Regular drag to reposition (only if not waiting for long press)
                    self.offset = CGSize(
                        width: savedOffsetX + value.translation.width,
                        height: savedOffsetY + value.translation.height
                    )
                }
            }
            .onEnded { value in
                isPressed = false
                longPressTask?.cancel()
                longPressTask = nil
                let distance = hypot(value.translation.width, value.translation.height)

                if isPieMenuExpanded {
                    // Handle pie menu selection
                    if let action = highlightedAction {
                        executeAction(action)
                    }

                    // Close pie menu
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isPieMenuExpanded = false
                        highlightedAction = nil
                    }
                } else if distance < 2 {
                    // Simple tap - open quick note sheet
                    self.offset = CGSize(width: savedOffsetX, height: savedOffsetY)
                    isShowingSheet = true
                } else {
                    // Drag ended - save new position
                    let finalOffset = CGSize(
                        width: savedOffsetX + value.translation.width,
                        height: savedOffsetY + value.translation.height
                    )
                    savedOffsetX = finalOffset.width
                    savedOffsetY = finalOffset.height

                    withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                        self.offset = finalOffset
                    }
                }

                dragTranslation = .zero
            }
    }

    private func startLongPressTask() {
        longPressTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: longPressDuration)

                // Check if still valid (not cancelled and finger hasn't moved)
                let distance = hypot(dragTranslation.width, dragTranslation.height)
                guard distance < 10 else { return }

                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isPieMenuExpanded = true
                }

                // Haptic feedback
                #if os(iOS)
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                #endif
            } catch {
                // Task was cancelled
            }
        }
    }

    private func updateHighlightedAction(translation: CGSize) {
        let distance = hypot(translation.width, translation.height)

        // Only highlight if dragged far enough from center
        guard distance > 25 else {
            highlightedAction = nil
            return
        }

        // Determine which segment based on vertical position
        // Top half = presentation, Bottom half = work item
        if translation.height < 0 {
            highlightedAction = .newPresentation
        } else {
            highlightedAction = .newWorkItem
        }
    }

    private func executeAction(_ action: PieMenuAction) {
        #if os(iOS)
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        #endif

        switch action {
        case .newPresentation:
            isShowingPresentationSheet = true
        case .newWorkItem:
            isShowingWorkItemSheet = true
        }
    }
}

// MARK: - Warning Banners

/// Warning banner displayed when using ephemeral/in-memory store.
struct EphemeralStoreWarningBanner: View {
    @Environment(\.appRouter) private var appRouter

    private var reason: String {
        UserDefaults.standard.string(forKey: UserDefaultsKeys.lastStoreErrorDescription)
        ?? "The persistent store could not be opened. Data will not persist this session."
    }

    private var isInMemoryMode: Bool {
        reason.contains("in-memory") || reason.contains("temporary")
    }

    private var warningTitle: String {
        isInMemoryMode ? "⚠️ SAFE MODE: CHANGES WILL NOT BE SAVED" : "Warning: Data won't persist this session"
    }

    private var warningMessage: String {
        isInMemoryMode
        ? "You are using an in-memory store. All data will be lost when you quit the app. Create a backup immediately!"
        : reason
    }

    private var iconColor: Color {
        isInMemoryMode ? .red : .yellow
    }

    private var titleColor: Color {
        isInMemoryMode ? .red : .primary
    }

    private var backgroundColor: AnyShapeStyle {
        isInMemoryMode ? AnyShapeStyle(Color.red.opacity(0.1)) : AnyShapeStyle(.ultraThinMaterial)
    }

    private var borderColor: Color {
        isInMemoryMode ? Color.red.opacity(0.3) : Color.primary.opacity(0.1)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(warningTitle)
                    .font(AppTheme.ScaledFont.callout.weight(.bold))
                    .foregroundStyle(titleColor)
                Text(warningMessage)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appRouter.requestCreateBackup()
            } label: {
                Label("Backup Now", systemImage: "externaldrive.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(isInMemoryMode ? .red : nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(borderColor),
            alignment: .bottom
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(warningTitle). \(warningMessage)")
        .accessibilityHint("Contains backup button")
    }
}

/// Warning banner displayed when CloudKit sync is enabled but not active.
struct CloudKitSyncWarningBanner: View {
    @Environment(\.appRouter) private var appRouter

    private var isiCloudSignedIn: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var errorDescription: String? {
        UserDefaults.standard.string(forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
    }

    private var warningTitle: String {
        if !isiCloudSignedIn {
            return "⚠️ Not Signed Into iCloud"
        } else if let error = errorDescription, !error.isEmpty {
            return "⚠️ CloudKit Init Failed"
        } else {
            return "⚠️ iCloud Sync Issue"
        }
    }

    private var warningMessage: String {
        if !isiCloudSignedIn {
            return "Sign in to iCloud in System Settings to enable sync across devices."
        } else if let error = errorDescription, !error.isEmpty {
            return error
        } else {
            return "Sync is enabled but not currently active."
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isiCloudSignedIn ? "icloud.slash" : "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(warningTitle)
                    .font(AppTheme.ScaledFont.callout.weight(.bold))
                Text(warningMessage)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                appRouter.navigateTo(.settings)
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.12))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.yellow.opacity(0.3)),
            alignment: .bottom
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(warningTitle). \(warningMessage)")
        .accessibilityHint("Contains settings button")
    }
}

// MARK: - Quick New Presentation Sheet

struct QuickNewPresentationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.sortIndex)])
    private var allLessons: [Lesson]

    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)])
    private var allStudentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    private var allStudents: [Student] { allStudentsRaw.uniqueByID }

    @State private var selectedLessonID: UUID?
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var lessonSearchText: String = ""
    @State private var studentSearchText: String = ""
    @State private var presentedAt: Date = Date()
    @State private var isSaving: Bool = false

    private var filteredLessons: [Lesson] {
        let query = lessonSearchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return allLessons }
        return allLessons.filter {
            $0.name.lowercased().contains(query) ||
            $0.subject.lowercased().contains(query) ||
            $0.group.lowercased().contains(query)
        }
    }

    private var filteredStudents: [Student] {
        let query = studentSearchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return allStudents }
        return allStudents.filter {
            $0.firstName.lowercased().contains(query) ||
            $0.lastName.lowercased().contains(query)
        }
    }

    private var selectedLesson: Lesson? {
        guard let id = selectedLessonID else { return nil }
        return allLessons.first { $0.id == id }
    }

    private var canSave: Bool {
        selectedLessonID != nil && !selectedStudentIDs.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Lesson Selection
                Section {
                    TextField("Search lessons...", text: $lessonSearchText)

                    if let lesson = selectedLesson {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(lesson.name)
                                    .font(.headline)
                                if !lesson.subject.isEmpty {
                                    Text(lesson.subject)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                selectedLessonID = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(filteredLessons.prefix(10)) { lesson in
                            Button {
                                selectedLessonID = lesson.id
                                lessonSearchText = ""
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(lesson.name)
                                    if !lesson.subject.isEmpty {
                                        Text(lesson.subject)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("Lesson")
                }

                // Student Selection
                Section {
                    TextField("Search students...", text: $studentSearchText)

                    if !selectedStudentIDs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(allStudents.filter { selectedStudentIDs.contains($0.id) }) { student in
                                    HStack(spacing: 4) {
                                        Text(StudentFormatter.displayName(for: student))
                                            .font(.caption)
                                        Button {
                                            selectedStudentIDs.remove(student.id)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                }
                            }
                        }
                    }

                    ForEach(filteredStudents.prefix(8)) { student in
                        Button {
                            if selectedStudentIDs.contains(student.id) {
                                selectedStudentIDs.remove(student.id)
                            } else {
                                selectedStudentIDs.insert(student.id)
                            }
                        } label: {
                            HStack {
                                Text(StudentFormatter.displayName(for: student))
                                Spacer()
                                if selectedStudentIDs.contains(student.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.accent)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    HStack {
                        Text("Students")
                        Spacer()
                        if !selectedStudentIDs.isEmpty {
                            Text("\(selectedStudentIDs.count) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Date
                Section {
                    DatePicker("Presented", selection: $presentedAt, displayedComponents: .date)
                }
            }
            .navigationTitle("Record Presentation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePresentation()
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 500, minHeight: 500)
        #endif
    }

    private func savePresentation() {
        guard let lessonID = selectedLessonID else { return }
        isSaving = true

        let studentIDStrings = selectedStudentIDs.map { $0.uuidString }
        let presentation = Presentation(
            createdAt: Date(),
            presentedAt: presentedAt,
            lessonID: lessonID.uuidString,
            studentIDs: studentIDStrings
        )

        // Snapshot lesson info
        if let lesson = selectedLesson {
            presentation.lessonTitleSnapshot = lesson.name
            presentation.lessonSubtitleSnapshot = lesson.subheading
        }

        modelContext.insert(presentation)
        _ = saveCoordinator.save(modelContext, reason: "Quick New Presentation")
        dismiss()
    }
}

// MARK: - Quick New Work Item Sheet

struct QuickNewWorkItemSheet: View {
    /// Optional callback when work is created and user wants to view details immediately
    var onCreatedAndOpen: ((UUID) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.sortIndex)])
    private var allLessons: [Lesson]

    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)])
    private var allStudentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    private var allStudents: [Student] { allStudentsRaw.uniqueByID }

    @State private var selectedLessonID: UUID?
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var workTitle: String = ""
    @State private var workKind: WorkKind = .practiceLesson
    @State private var dueDate: Date? = nil
    @State private var hasDueDate: Bool = false
    @State private var lessonSearchText: String = ""
    @State private var isSaving: Bool = false

    // Popover states
    @State private var showingLessonPopover: Bool = false
    @State private var showingStudentPopover: Bool = false
    @FocusState private var lessonFieldFocused: Bool

    private var filteredLessons: [Lesson] {
        let query = lessonSearchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return allLessons }
        return allLessons.filter {
            $0.name.lowercased().contains(query) ||
            $0.subject.lowercased().contains(query) ||
            $0.group.lowercased().contains(query)
        }
    }

    private var selectedLesson: Lesson? {
        guard let id = selectedLessonID else { return nil }
        return allLessons.first { $0.id == id }
    }

    private var selectedStudents: [Student] {
        allStudents.filter { selectedStudentIDs.contains($0.id) }
    }

    private var canSave: Bool {
        selectedLessonID != nil && !selectedStudentIDs.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    Text("New Work")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    // Lesson Section
                    lessonSection()

                    Divider()

                    // Student Section
                    studentSection()

                    Divider()

                    // Details Section
                    detailsSection()
                }
                .padding(24)
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if onCreatedAndOpen != nil && selectedStudentIDs.count == 1 {
                    Button("Create & Open") { saveWorkItem(andOpen: true) }
                        .disabled(!canSave || isSaving)
                }
                Button("Create") { saveWorkItem(andOpen: false) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave || isSaving)
            }
            .padding(16)
            .background(.bar)
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 500, minHeight: 500)
        #endif
    }

    // MARK: - Lesson Section

    @ViewBuilder
    private func lessonSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lesson")
                .font(.headline)

            // Search field with popover
            TextField("Search lessons...", text: $lessonSearchText)
                .textFieldStyle(.roundedBorder)
                .focused($lessonFieldFocused)
                .onChange(of: lessonSearchText) { _, newValue in
                    if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        showingLessonPopover = true
                    }
                }
                .onSubmit {
                    // If user typed an exact lesson name, select it
                    let trimmed = lessonSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let match = filteredLessons.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
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
                            .font(.subheadline.weight(.semibold))
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
                .padding(12)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            } else {
                Text("Choose a lesson to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func lessonPopoverContent() -> some View {
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
                                .foregroundColor(.accentColor)
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
        .padding(8)
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #else
        .frame(minHeight: 300)
        #endif
    }

    private func selectLesson(_ lesson: Lesson) {
        selectedLessonID = lesson.id
        lessonSearchText = lesson.name
        showingLessonPopover = false
        lessonFieldFocused = false

        // Auto-set work title if empty
        if workTitle.isEmpty {
            workTitle = lesson.name
        }
    }

    // MARK: - Student Section

    private func removeStudent(id: UUID) {
        _ = withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            selectedStudentIDs.remove(id)
        }
    }

    @ViewBuilder
    private func studentChip(for student: Student) -> some View {
        HStack(spacing: 4) {
            Text(StudentFormatter.displayName(for: student))
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.15))
                .foregroundColor(.accentColor)
                .clipShape(Capsule())

            Button {
                removeStudent(id: student.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func studentSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Student")
                .font(.headline)

            HStack(alignment: .center, spacing: 8) {
                // Selected students as chips
                if !selectedStudents.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedStudents) { student in
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
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: selectedStudentIDs)

            if selectedStudentIDs.isEmpty {
                Text("Add at least one student.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Details Section

    @ViewBuilder
    private func detailsSection() -> some View {
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
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))

            // Due date toggle and picker
            Toggle("Set due date", isOn: $hasDueDate)

            if hasDueDate {
                DatePicker("Due date", selection: Binding(
                    get: { dueDate ?? Date() },
                    set: { dueDate = $0 }
                ), displayedComponents: .date)
            }
        }
    }

    @ViewBuilder
    private func kindButton(_ kind: WorkKind, _ label: String) -> some View {
        Button(label) {
            workKind = kind
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(workKind == kind ? Color.accentColor.opacity(0.1) : Color.clear)
        .foregroundStyle(workKind == kind ? Color.accentColor : .primary)
        .font(.subheadline)
    }

    // MARK: - Save

    private func saveWorkItem(andOpen: Bool) {
        guard let lessonID = selectedLessonID,
              !selectedStudentIDs.isEmpty else { return }
        isSaving = true

        let repository = WorkRepository(context: modelContext)

        do {
            var createdWorkID: UUID?
            // Create work for each selected student
            for studentID in selectedStudentIDs {
                let work = try repository.createWork(
                    studentID: studentID,
                    lessonID: lessonID,
                    title: workTitle.isEmpty ? nil : workTitle,
                    kind: workKind,
                    scheduledDate: hasDueDate ? dueDate : nil
                )
                // Keep reference to first created work for "Create & Open"
                if createdWorkID == nil {
                    createdWorkID = work.id
                }
            }
            _ = saveCoordinator.save(modelContext, reason: "Quick New Work Item")
            dismiss()

            // If user wants to open the detail view, call the callback after dismiss
            if andOpen, let workID = createdWorkID {
                onCreatedAndOpen?(workID)
            }
        } catch {
            isSaving = false
        }
    }
}
