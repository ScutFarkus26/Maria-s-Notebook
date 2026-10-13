import SwiftUI

/// Match Names (notebook only; Phase 3 places it in Settings): the class's
/// children beside ParentLocker's, with the ones the app couldn't match by
/// name first. Picking the right ParentLocker child stores it on the student
/// (`parentLockerID`), so later syncs go by ID and survive a rename; only the
/// lead guide's devices write it, and a test copy of the app (a Debug build)
/// never does (`ParentLockerSavePolicy`). Reads ParentLocker, never saves to it.
struct ParentLockerMatchView: View {

    let sync: ParentLockerSync

    @State private var rows: [Row] = []
    @State private var people: [Person] = []
    @State private var isLoading = true
    @State private var errorText: String?
    /// Why the last pick wasn't saved.
    @State private var pickText: String?

    /// A notebook child and what matching made of them.
    struct Row: Identifiable, Equatable {
        let id: UUID
        let name: String
        var studentID: String?
        /// Neither a stored ID nor exactly one name matched.
        let needsYou: Bool
    }

    /// A ParentLocker child, as the picker lists them.
    struct Person: Identifiable, Equatable {
        let id: String
        let label: String
    }

    var body: some View {
        Form {
            if isLoading {
                ProgressView("Reading ParentLocker…")
            } else if let errorText {
                Text(errorText)
                    .foregroundStyle(.secondary)
            } else {
                let unsure = rows.filter(\.needsYou)
                if !unsure.isEmpty {
                    Section {
                        ForEach(unsure) { row in picker(for: row) }
                    } header: {
                        Text("Not matched yet")
                    } footer: {
                        Text("Pick the ParentLocker child for each. Children left unmatched aren't sent.")
                    }
                }
                Section("Matched") {
                    ForEach(rows.filter { !$0.needsYou }) { row in picker(for: row) }
                }
                if let pickText {
                    Section {
                        Text(pickText)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Match Names")
        .task { await load() }
    }

    private func picker(for row: Row) -> some View {
        Picker(row.name, selection: Binding(
            get: { row.studentID },
            set: { choose($0, for: row) }
        )) {
            Text("Not matched").tag(String?.none)
            ForEach(people) { person in
                Text(person.label).tag(Optional(person.id))
            }
        }
    }

    private func choose(_ studentID: String?, for row: Row) {
        let role = sync.store.day(sync.today, withChildren: false).role
        if let refusal = Self.refusal(policy: sync.dependencies.policy, role: role) {
            pickText = refusal
            return
        }
        guard sync.store.writeMatches([row.id: studentID]) else {
            pickText = Self.saveFailed
            return
        }
        pickText = nil
        if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index].studentID = studentID }
    }

    nonisolated static let saveFailed = "Couldn't save the match. Try again."

    /// Why a pick can't be saved on this device, before trying: a test copy
    /// only previews, and only the guide matches names.
    nonisolated static func refusal(
        policy: ParentLockerSavePolicy, role: CDClassroomMembership.ClassroomRole
    ) -> String? {
        if !policy.allowsSaving { return "This test copy of the app only previews, so the match wasn't saved." }
        if role != .leadGuide { return "Only the guide can match names." }
        return nil
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard sync.isSignedIn else {
            errorText = "Sign in to ParentLocker first."
            return
        }
        let today = sync.today
        let rosters: [ParentLockerRoster]
        do {
            rosters = try await sync.loadRosters(day: today)
        } catch let stop as ParentLockerSyncStop {
            errorText = stop.message
            return
        } catch {
            errorText = AppErrorMessages.userMessage(for: error, context: "reading ParentLocker")
            return
        }
        let day = sync.store.day(today, withChildren: true)
        let matches = ParentLockerPlanner.match(children: day.children, rosters: rosters)
        rows = day.children.map { child in
            let match = matches[child.id] ?? .unmatched
            var studentID: String?
            if case .matched(let id, _) = match { studentID = id }
            return Row(id: child.id, name: day.name(of: child.id), studentID: studentID, needsYou: studentID == nil)
        }
        .sorted { ($0.needsYou ? 0 : 1, $0.name) < ($1.needsYou ? 0 : 1, $1.name) }
        people = Self.people(in: rosters)
        errorText = nil
    }

    /// Every child on the rosters once, "Juniper Ashby (June) · Girls Middle School".
    static func people(in rosters: [ParentLockerRoster]) -> [Person] {
        var seen = Set<String>()
        var people: [Person] = []
        for roster in rosters {
            for student in roster.students where seen.insert(student.studentID).inserted {
                let alternate = student.alternateName.trimmingCharacters(in: .whitespaces)
                let name = "\(student.firstName) \(student.lastName)" + (alternate.isEmpty ? "" : " (\(alternate))")
                people.append(Person(id: student.studentID, label: "\(name) · \(roster.course.name)"))
            }
        }
        return people.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
}
