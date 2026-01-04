import SwiftUI
#if canImport(AppIntents)
import AppIntents
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

struct SummarySnippetView: View {
    var title: String?
    var bodyText: String?
    var bullets: [String]
    var followUps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title)
                    .font(.headline)
            }
            if let bodyText = bodyText {
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
                        .foregroundColor(.secondary)
                    ForEach(followUps, id: \.self) { followUp in
                        Text("• \(followUp)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
    }
}

#if canImport(AppIntents)
@available(iOS 16, macOS 13, *)
struct SummarizeTodaysObservationsIntent: AppIntent, SnippetIntent {
    static var title: LocalizedStringResource = "Summarize Today's Observations"
    static var description = IntentDescription("Provides a summary snippet of today's observations.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result()
    }

    var snippet: some View {
        SummarySnippetView(
            title: "Today's Summary",
            bodyText: nil,
            bullets: [
                "Observed increased user engagement in the morning hours.",
                "Noted a drop in error rates compared to yesterday.",
                "Received positive feedback from beta testers."
            ],
            followUps: [
                "Review detailed analytics report.",
                "Plan team meeting for feedback discussion."
            ]
        )
    }
}
#endif

