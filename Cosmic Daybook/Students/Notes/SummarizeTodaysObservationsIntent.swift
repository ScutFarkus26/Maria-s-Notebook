import SwiftUI
import CoreData
#if canImport(AppIntents)
import AppIntents
#endif

struct SummarySnippetView: View {
    var title: String?
    var bodyText: String?
    var bullets: [String]
    var followUps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            if let bodyText {
                Text(bodyText)
                    .font(.body)
            }
            if !bullets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(bullets, id: \.self) { bullet in
                        HStack(alignment: .top) {
                            Text("•")
                            Text(bullet)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !followUps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Follow-ups:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(followUps, id: \.self) { followUp in
                        Text("• \(followUp)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
    }
}

#if canImport(AppIntents)
// MARK: - Today's observations data

/// Loads a glanceable list of today's observation notes for the snippet.
enum TodayObservationsData {
    @MainActor
    static func todayBullets(limit: Int = 8) -> [String] {
        let context = AppBootstrapping.getSharedCoreDataStack().viewContext
        let (start, end) = AppCalendar.dayRange(for: Date())

        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(
            format: "createdAt >= %@ AND createdAt < %@",
            start as NSDate, end as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: false)]
        request.fetchLimit = limit

        return context.safeFetch(request).map { note in
            let trimmed = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = trimmed.count > 100 ? String(trimmed.prefix(100)) + "…" : trimmed
            if let name = studentFirstName(for: note, in: context) {
                return "\(name): \(body)"
            }
            return body
        }
    }

    @MainActor
    private static func studentFirstName(for note: CDNote, in context: NSManagedObjectContext) -> String? {
        guard let studentID = note.searchIndexStudentID else { return nil }
        return context.object(CDStudent.self, id: studentID)?.firstName
    }
}

// MARK: - Snippet view

/// Loads today's observations on appearance and renders them, with a button to
/// jump into the Today view.
struct TodayObservationsSnippetView: View {
    @State private var bullets: [String] = []
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummarySnippetView(
                title: "Today's Observations",
                bodyText: (didLoad && bullets.isEmpty) ? "No observations logged today yet." : nil,
                bullets: bullets,
                followUps: []
            )
            Button(intent: OpenTodayIntent()) {
                Label("Open Today", systemImage: "arrow.forward.circle")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .task {
            guard !didLoad else { return }
            bullets = TodayObservationsData.todayBullets()
            didLoad = true
        }
    }
}

struct SummarizeTodaysObservationsIntent: AppIntent, SnippetIntent {
    /// Marked nonisolated(unsafe) because AppIntent static metadata properties are accessed
    /// from the system's intent infrastructure, which operates outside our actor isolation.
    /// Safe because these are immutable static properties initialized at compile time.
    nonisolated(unsafe) static var title: LocalizedStringResource = "Show Today's Observations"
    nonisolated(unsafe) static var description = IntentDescription(
        "Shows a snippet of today's observations."
    )
    nonisolated(unsafe) static var openAppWhenRun: Bool = false
    /// Surfaces student observations outside the app, so require the device be unlocked.
    nonisolated(unsafe) static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result()
    }

    /// Snippets render SwiftUI content, so construct this view on the main
    /// actor even when App Intents asks for the intent from another context.
    @MainActor
    var snippet: some View {
        TodayObservationsSnippetView()
    }
}
#endif
