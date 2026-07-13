import SwiftUI

/// Keeps all child-specific observation work together while making the factual
/// notes timeline the default. Developmental characteristics remain available
/// as a view of observations, rather than competing as a peer record type.
struct StudentObserveWorkspace: View {
    private enum ViewMode: String {
        case timeline
        case characteristics

        var title: String {
            switch self {
            case .timeline: "Observation Timeline"
            case .characteristics: "Developmental Characteristics"
            }
        }
    }

    let student: CDStudent
    @State private var viewMode: ViewMode = .timeline
    @State private var showingGuideReview = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(viewMode.title)
                    .font(.headline)
                Spacer()
                Menu {
                    Button("Observation Timeline", systemImage: "note.text") {
                        viewMode = .timeline
                    }
                    Button("Developmental Characteristics", systemImage: "leaf") {
                        viewMode = .characteristics
                    }
                    Divider()
                    Button("Guide Review…", systemImage: "brain.head.profile") {
                        showingGuideReview = true
                    }
                } label: {
                    Label("View", systemImage: "rectangle.3.group")
                }
                .help("Choose an observation view")
            }
            .padding(.horizontal, 32)
            .padding(.top, 18)
            .padding(.bottom, 8)

            Divider()

            switch viewMode {
            case .timeline:
                StudentNotesTab(student: student)
            case .characteristics:
                DevelopmentalTraitsView(studentID: student.id ?? UUID())
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingGuideReview) {
            NavigationStack {
                StudentInsightsView(student: student)
            }
        }
    }
}
