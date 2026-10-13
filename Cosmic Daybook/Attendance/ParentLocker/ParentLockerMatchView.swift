import SwiftUI

/// Match Names (notebook only; Phase 3 places it in Settings): the class's
/// children beside ParentLocker's, with the ones the app couldn't match by
/// name first. Picking the right ParentLocker child stores it on the student
/// (`parentLockerID`), so later syncs go by ID and survive a rename, and
/// takes that ParentLocker child from whoever held it; "Not matched" stores
/// `ParentLockerPlanner.notMatchedID`, which leaves the child out for good.
/// Only the lead guide's devices write it, and a test copy of the app (a
/// Debug build) never does (`ParentLockerSavePolicy`). Reads ParentLocker,
/// never saves to it.
struct ParentLockerMatchView: View {

    let sync: ParentLockerSync

    @State private var rows: [Row] = []
    @State private var people: [Person] = []
    /// The rosters read on opening, to match again after each pick.
    @State private var rosters: [ParentLockerRoster] = []
    @State private var isLoading = true
    @State private var errorText: String?
    /// Why the last pick wasn't saved.
    @State private var pickText: String?

    /// A notebook child and what matching made of them.
    struct Row: Identifiable, Equatable {
        let id: UUID
        let name: String
        /// The ParentLocker child, `notMatchedID` when left out, nil when unsure.
        var studentID: String?
        /// Neither a stored ID nor exactly one name matched, and the guide
        /// hasn't left them out.
        let needsYou: Bool

        var isLeftOut: Bool { studentID == ParentLockerPlanner.notMatchedID }
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
                        Text("Pick the ParentLocker child for each, or Not matched to leave them out. "
                            + "Children who aren't matched aren't sent.")
                    }
                }
                let matched = rows.filter { !$0.needsYou && !$0.isLeftOut }
                if !matched.isEmpty {
                    Section("Matched") {
                        ForEach(matched) { row in picker(for: row) }
                    }
                }
                let leftOut = rows.filter(\.isLeftOut)
                if !leftOut.isEmpty {
                    Section {
                        ForEach(leftOut) { row in picker(for: row) }
                    } header: {
                        Text("Not sent")
                    } footer: {
                        Text("These children are never sent to ParentLocker. Pick a child to send them again.")
                    }
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
            if row.studentID == nil {
                Text("Choose a child").tag(String?.none)
            }
            Text("Not matched").tag(Optional(ParentLockerPlanner.notMatchedID))
            ForEach(people) { person in
                Text(person.label).tag(Optional(person.id))
            }
        }
    }

    private func choose(_ studentID: String?, for row: Row) {
        guard let studentID, studentID != row.studentID else { return }
        let role = sync.store.day(sync.today, withChildren: false).role
        if let refusal = Self.refusal(policy: sync.dependencies.policy, role: role) {
            pickText = refusal
            return
        }
        let displaced = Self.displaced(by: studentID, picking: row.id, in: rows)
        guard sync.store.writeMatches([row.id: studentID]) else {
            pickText = Self.saveFailed
            return
        }
        pickText = nil
        Self.notePick(of: row.id, displacing: displaced, in: sync)
        // Match again: whoever held this ParentLocker child now needs one.
        let day = sync.store.day(sync.today, withChildren: true)
        let matches = ParentLockerPlanner.match(children: day.children, rosters: rosters)
        rows = Self.rows(children: day.children, matches: matches, name: day.name(of:))
    }

    nonisolated static let saveFailed = "Couldn't save the match. Try again."

    /// The child who held `studentID` before `picked` took it, if anyone.
    static func displaced(by studentID: String, picking picked: UUID, in rows: [Row]) -> UUID? {
        guard !ParentLockerPlanner.isNotMatched(studentID) else { return nil }
        return rows.first { $0.studentID == studentID && $0.id != picked }?.id
    }

    /// A pick made once today is past "after" goes to ParentLocker as this
    /// device's own change: a child matched after the class went would
    /// otherwise wait for their next mark, and the watcher doesn't follow
    /// student saves (bug hunt 2026-10-13 afternoon, M7). Before "after",
    /// the whole-class send covers them.
    static func notePick(of picked: UUID, displacing displaced: UUID?, in sync: ParentLockerSync) {
        let today = sync.today
        guard sync.isAfter(sync.store.day(today, withChildren: false), on: today) else { return }
        sync.noteChanges(Set([picked] + (displaced.map { [$0] } ?? [])), imported: false, on: today)
    }

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
        rows = Self.rows(children: day.children, matches: matches, name: day.name(of:))
        people = Self.people(in: rosters)
        self.rosters = rosters
        errorText = nil
    }

    /// The rows for `children`, the ones that need the guide first.
    static func rows(
        children: [ParentLockerPlanner.Child],
        matches: [UUID: ParentLockerPlanner.Match],
        name: (UUID) -> String
    ) -> [Row] {
        children.map { child in
            let studentID: String? = switch matches[child.id] ?? .unmatched {
            case .matched(let id, _): id
            case .leftOut: ParentLockerPlanner.notMatchedID
            case .unmatched, .ambiguous: nil
            }
            return Row(id: child.id, name: name(child.id), studentID: studentID, needsYou: studentID == nil)
        }
        .sorted { ($0.needsYou ? 0 : 1, $0.name) < ($1.needsYou ? 0 : 1, $1.name) }
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
