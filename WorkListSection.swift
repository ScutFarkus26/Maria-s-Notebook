import SwiftUI

struct WorkListSection: View {
    let works: [WorkModel]
    let workTitle: (WorkModel) -> String
    let workSubtitle: (WorkModel) -> String?
    let iconAndColor: (WorkModel.WorkType) -> (String, Color)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Working on")
                    .font(.system(size: AppTheme.FontSize.header, weight: .heavy, design: .rounded))
                Spacer()
                Text("\(works.count)")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            if works.isEmpty {
                Text("No work recorded yet.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else {
                VStack(spacing: 10) {
                    ForEach(works, id: \.id) { work in
                        WorkListRow(
                            work: work,
                            workTitle: workTitle,
                            workSubtitle: workSubtitle,
                            iconAndColor: iconAndColor
                        )
                    }
                }
            }
        }
    }
}

struct WorkListRow: View {
    let work: WorkModel
    let workTitle: (WorkModel) -> String
    let workSubtitle: (WorkModel) -> String?
    let iconAndColor: (WorkModel.WorkType) -> (String, Color)

    var body: some View {
        HStack(spacing: 12) {
            let pair = iconAndColor(work.workType)
            Image(systemName: pair.0)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(pair.1)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(workTitle(work))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                if let subtitle = workSubtitle(work), !subtitle.isEmpty {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    Text("WorkListSection requires real data")
}
