import SwiftUI
import SwiftData

struct TopicRowView: View {
    let topic: CommunityTopic
    let onSelect: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @State private var solutionCount: Int?

    var body: some View {
        let isResolved = topic.isResolved
        let titleText = topic.title
        let issueText = topic.issueDescription
        let resolutionText = topic.resolution.trimmed()
        let count = solutionCount ?? 0
        let solutionsLabel = count == 1 ? "solution" : "solutions"
        let raisedBy = topic.raisedBy.trimmed()

        Group {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: isResolved ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isResolved ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(titleText)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text((topic.addressedDate ?? topic.createdAt), style: .date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if !raisedBy.isEmpty {
                        Text("Raised by: \(raisedBy)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(issueText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if isResolved && !resolutionText.isEmpty {
                        Text(resolutionText)
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb")
                            .foregroundStyle(Color.accentColor)
                        Text("\(count) \(solutionsLabel)")
                            .font(.footnote)
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2))
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.04))
                    )
            )
        }
        .task(id: topic.id) {
            if solutionCount == nil {
                do {
                    let tid = topic.id
                    let descriptor = FetchDescriptor<ProposedSolution>(
                        predicate: #Predicate { s in
                            s.topic?.id == tid
                        }
                    )
                    let items = try modelContext.fetch(descriptor)
                    solutionCount = items.count
                } catch {
                    solutionCount = 0
                }
            }
        }
        .onTapGesture(perform: onSelect)
    }
}
