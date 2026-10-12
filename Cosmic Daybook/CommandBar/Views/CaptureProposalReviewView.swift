import SwiftUI
/// The review of one free-form classroom capture before anything is saved.
struct CaptureProposalReviewView: View {
    @Binding var proposal: CaptureProposal
    let students: [CDStudent]
    let lessons: [CDLesson]
    let validationMessage: String?
    let saveTitle: String
    var isSaving: Bool = false
    var onSave: () -> Void
    var onStartOver: (() -> Void)?

    @State private var individualDetailsExpanded = false

    private var hasIndividualDetails: Bool {
        proposal.studentEntries.contains {
            !$0.observation.trimmed().isEmpty || $0.followUp != .none
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                privacyDisclosure
                presentationReviewCard
                studentsReviewCard
                observationsReviewCard

                if let validationMessage {
                    Label(validationMessage, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                Button(action: onSave) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(saveTitle)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .disabled(validationMessage != nil || isSaving)
                .accessibilityHint("Nothing is saved until this button is pressed")

                if let onStartOver {
                    Button("Start Over", action: onStartOver)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .onAppear {
            individualDetailsExpanded = hasIndividualDetails
        }
        .onChange(of: hasIndividualDetails) { _, hasDetails in
            if hasDetails { individualDetailsExpanded = true }
        }
    }
}

private extension CaptureProposalReviewView {
    private var privacyDisclosure: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: proposal.source.icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(proposal.source.disclosure)
                    .font(.subheadline.weight(.semibold))
                Text("This is an editable proposal. Nothing below is saved until you confirm it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            Color.blue.opacity(UIConstants.OpacityConstants.veryFaint),
            in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
        )
    }

    private var presentationReviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Presentation", systemImage: "person.crop.rectangle.stack")
                .font(.headline)

            Toggle("A lesson was given", isOn: proposalBinding(\.recordsPresentation))

            Picker("Lesson", selection: lessonSelectionBinding) {
                Text("Choose a lesson").tag(nil as UUID?)
                ForEach(lessons.uniqueByID) { lesson in
                    if let id = lesson.id {
                        Text(lesson.name).tag(id as UUID?)
                    }
                }
            }
            .disabled(!proposal.recordsPresentation)

            // The day it happened: read from her words ("yesterday", "on
            // Tuesday"), today otherwise, and never a day still to come. The
            // presentation and the notes are saved on it.
            DatePicker(
                proposal.recordsPresentation ? "Given on" : "Seen on",
                selection: Binding(
                    get: { proposal.presentedOn },
                    set: { proposal.presentedOn = AppCalendar.startOfDay($0) }
                ),
                in: ...Date(),
                displayedComponents: .date
            )
        }
        .padding(14)
        .background(
            Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint),
            in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
        )
    }

    private var studentsReviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Children", systemImage: "person.2")
                    .font(.headline)
                Spacer()
                studentSelectionMenu
            }

            ForEach(proposal.unresolvedStudentNames, id: \.self) { name in
                unplacedNameRow(name)
            }

            if proposal.studentEntries.isEmpty {
                Text("No children selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 7) {
                    ForEach(proposal.studentEntries) { entry in
                        Label(entry.studentName, systemImage: "person.fill")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(UIConstants.OpacityConstants.medium), in: Capsule())
                    }
                }
            }
        }
        .padding(14)
        .background(
            Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint),
            in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
        )
    }

    /// A name the organizer couldn't place on one child, with what was said
    /// about her. Picking her with Edit settles it; Leave Out says it's nobody
    /// in the class. Save waits until one or the other.
    private func unplacedNameRow(_ name: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Who is “\(name)”? Pick the child with Edit.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                if let said = proposal.unplacedWords[name]?.observation, !said.isEmpty {
                    Text("You said: \(said)")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Leave Out") {
                proposal.leaveOutUnplacedName(name)
            }
            .buttonStyle(.borderless)
        }
        .font(.footnote)
    }

    private var studentSelectionMenu: some View {
        Menu {
            ForEach(students.uniqueByID) { student in
                if let id = student.id {
                    let selected = proposal.studentEntries.contains { $0.studentID == id }
                    Button {
                        setStudent(student, isSelected: !selected)
                    } label: {
                        Label(
                            student.shortName,
                            systemImage: selected ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
            }
        } label: {
            Label("Edit", systemImage: "person.badge.plus")
        }
        .menuStyle(.button)
    }
}

private extension CaptureProposalReviewView {
    private var observationsReviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Observations and next steps", systemImage: "text.bubble")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Shared observation")
                    .font(.subheadline.weight(.semibold))
                TextField(
                    "What was true for the whole group?",
                    text: proposalBinding(\.groupObservation),
                    axis: .vertical
                )
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            }

            if !proposal.studentEntries.isEmpty {
                Divider()

                DisclosureGroup(isExpanded: $individualDetailsExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(proposal.studentEntries) { entry in
                            studentObservationEditor(entry)
                            if entry.id != proposal.studentEntries.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    HStack {
                        Label("Individual observations and follow-up", systemImage: "person.text.rectangle")
                        Spacer()
                        if hasIndividualDetails {
                            Text("Added")
                                .font(.caption)
                                .foregroundStyle(AppColors.success)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            if !proposal.rawText.trimmed().isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Original words")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Text(proposal.rawText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .background(
            Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint),
            in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
        )
    }

    private func studentObservationEditor(_ entry: StudentCaptureProposal) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(entry.studentName)
                .font(.subheadline.weight(.semibold))

            TextField(
                "What did you observe?",
                text: studentObservationBinding(entry.id),
                axis: .vertical
            )
            .lineLimit(2...5)
            .textFieldStyle(.roundedBorder)

            Picker("Next step", selection: studentFollowUpBinding(entry.id)) {
                ForEach(CaptureFollowUp.allCases) { followUp in
                    Label(followUp.displayName, systemImage: followUp.icon).tag(followUp)
                }
            }
            .pickerStyle(.menu)

            if entry.followUp == .practice || entry.followUp == .followUpWork {
                TextField(
                    entry.followUp == .practice ? "Practice title (optional)" : "Describe the follow-up work",
                    text: studentFollowUpDetailBinding(entry.id)
                )
                .textFieldStyle(.roundedBorder)
            }
        }
    }
}

private extension CaptureProposalReviewView {
    private func proposalBinding<Value>(_ keyPath: WritableKeyPath<CaptureProposal, Value>) -> Binding<Value> {
        Binding(
            get: { proposal[keyPath: keyPath] },
            set: { proposal[keyPath: keyPath] = $0 }
        )
    }

    private var lessonSelectionBinding: Binding<UUID?> {
        Binding(
            get: { proposal.lessonID },
            set: { value in
                proposal.lessonID = value
                proposal.lessonName = value.flatMap { id in
                    lessons.first(where: { $0.id == id })?.name
                }
            }
        )
    }

    private func studentObservationBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { proposal.studentEntries.first(where: { $0.id == id })?.observation ?? "" },
            set: { value in updateStudentEntry(id: id) { $0.observation = value } }
        )
    }

    private func studentFollowUpBinding(_ id: UUID) -> Binding<CaptureFollowUp> {
        Binding(
            get: { proposal.studentEntries.first(where: { $0.id == id })?.followUp ?? .none },
            set: { value in
                updateStudentEntry(id: id) {
                    $0.followUp = value
                    if value == .none || value == .represent || value == .readyForNextLesson {
                        $0.followUpDetail = ""
                    }
                }
            }
        )
    }

    private func studentFollowUpDetailBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { proposal.studentEntries.first(where: { $0.id == id })?.followUpDetail ?? "" },
            set: { value in updateStudentEntry(id: id) { $0.followUpDetail = value } }
        )
    }

    private func updateStudentEntry(id: UUID, update: (inout StudentCaptureProposal) -> Void) {
        guard let index = proposal.studentEntries.firstIndex(where: { $0.id == id }) else { return }
        update(&proposal.studentEntries[index])
    }

    private func setStudent(_ student: CDStudent, isSelected: Bool) {
        guard let id = student.id else { return }
        let roster = students.uniqueByID.compactMap { child -> StudentData? in
            guard let childID = child.id else { return nil }
            return StudentData(
                id: childID, firstName: child.firstName, lastName: child.lastName, nickname: child.nickname
            )
        }
        proposal.setStudent(
            StudentData(id: id, firstName: student.firstName, lastName: student.lastName, nickname: student.nickname),
            named: student.shortName,
            isSelected: isSelected,
            roster: roster
        )
    }
}
