import SwiftUI

struct TopicRowView: View {
    let topic: CommunityTopic
    let onSelect: () -> Void

    var body: some View {
        let isResolved = topic.isResolved
        let titleText = topic.title
        let issueText = topic.issueDescription
        let resolutionText = topic.resolution.trimmingCharacters(in: .whitespacesAndNewlines)
        let solutionsCount = topic.proposedSolutions.count
        let solutionsLabel = solutionsCount == 1 ? "solution" : "solutions"
        let raisedBy = topic.raisedBy.trimmingCharacters(in: .whitespacesAndNewlines)

        Group {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: isResolved ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isResolved ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(titleText)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Text((topic.addressedDate ?? topic.createdAt), style: .date)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if !raisedBy.isEmpty {
                        Text("Raised by: \(raisedBy)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(issueText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if isResolved && !resolutionText.isEmpty {
                        Text(resolutionText)
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb")
                            .foregroundColor(.accentColor)
                        Text("\(solutionsCount) \(solutionsLabel)")
                            .font(.footnote)
                            .foregroundColor(.accentColor)
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
        .onTapGesture(perform: onSelect)
    }
}

