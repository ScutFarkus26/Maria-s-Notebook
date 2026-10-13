import SwiftUI

/// Match Names (notebook only; Phase 3 places it in Settings): the class's
/// children beside ParentLocker's, with the ones the app couldn't match by
/// name first. Picking the right ParentLocker child stores it on the student
/// (`parentLockerID`), so later syncs go by ID and survive a rename; only the
/// lead guide's devices write it. Reads ParentLocker, never saves to it.
struct ParentLockerMatchView: View {

    let sync: ParentLockerSync

    @State private var rows: [Row] = []
    @State private var people: [Person] = []
    @State private var isLoading = true
    @State private var errorText: String?

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
        guard sync.store.writeMatches([row.id: studentID]) else {
            errorText = "Couldn't save the match. Only the lead guide's devices can match names."
            return
        }
        if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index].studentID = studentID }
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
