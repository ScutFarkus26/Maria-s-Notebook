import SwiftUI

struct WorkingOnListView: View {
    let isLoading: Bool
    let works: [WorkModel]
    let countText: String
    let titleForWork: (WorkModel) -> String
    let subtitleForWork: (WorkModel) -> String?
    let iconAndColorForType: (WorkModel.WorkType) -> (String, Color)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Working on")
                    .font(.system(size: AppTheme.FontSize.header, weight: .heavy, design: .rounded))
                Spacer()
                Text(countText)
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            if isLoading {
                Text("Loading…")
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else if works.isEmpty {
                Text("No work recorded yet.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else {
                VStack(spacing: 10) {
                    ForEach(works, id: \.id) { work in
                        HStack(spacing: 12) {
                            let pair = iconAndColorForType(work.workType)
                            Image(systemName: pair.0)
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundStyle(pair.1)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(titleForWork(work))
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                if let subtitle = subtitleForWork(work), !subtitle.isEmpty {
                                    Text(subtitle)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}
