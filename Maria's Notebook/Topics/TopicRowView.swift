import SwiftUI
import CoreData

struct TopicRowView: View {
    let topic: CDCommunityTopicEntity
    let onSelect: () -> Void

    var body: some View {
        topicCard
            .onTapGesture(perform: onSelect)
    }

    private var topicCard: some View {
        let isResolved: Bool = topic.isResolved
        // Read the count straight off the (prefetched) relationship instead of
        // firing a per-row CDProposedSolutionEntity fetch. The parent renders
        // every row eagerly, so the old `.task` fetch was an N+1 over the list;
        // CommunityMeetingsView now prefetches `proposedSolutions` so this hits
        // the row cache.
        let count: Int = topic.proposedSolutions?.count ?? 0
        let raisedBy: String = topic.raisedBy.trimmed()

        return HStack(alignment: .top, spacing: 16) {
            Image(systemName: isResolved ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isResolved ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(topic.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text((topic.addressedDate ?? topic.createdAt ?? Date()), style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !raisedBy.isEmpty {
                    Text("Raised by: \(raisedBy)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(topic.issueDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if isResolved && !topic.resolution.trimmed().isEmpty {
                    Text(topic.resolution.trimmed())
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 4) {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(Color.accentColor)
                    Text("\(count) \(count == 1 ? "solution" : "solutions")")
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
                .stroke(Color.gray.opacity(UIConstants.OpacityConstants.moderate))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                )
        )
    }
}
