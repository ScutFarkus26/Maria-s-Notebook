import SwiftUI
import SwiftData

struct ProgressReportPrintView: View {
    let student: Student
    let report: StudentProgressReport

    private var groupedRatings: [(domain: String, entries: [ReportRatingEntry])] {
        var order: [String] = []
        var buckets: [String: [ReportRatingEntry]] = [:]
        for e in report.ratings {
            if buckets[e.domain] == nil { order.append(e.domain); buckets[e.domain] = [] }
            buckets[e.domain]?.append(e)
        }
        let grouped = order.map { (domain: $0, entries: buckets[$0] ?? []) }
        let filteredDomains = grouped.filter { !["Kriah","Chumash","Kesivah","Taryag Mitzvos","Navi/Yamim Tovim"].contains($0.domain) }
        let filteredNoStoryline = filteredDomains.map { (domain: $0.domain, entries: $0.entries.filter { $0.skillLabel.range(of: "Storyline", options: .caseInsensitive) == nil }) }
        return filteredNoStoryline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("\(student.fullName)")
                    .font(.title.bold())
                HStack(spacing: 12) {
                    Text("Year: \(report.schoolYear)")
                    Text("Teacher: \(report.teacher)")
                    Text("Grade: \(report.grade)")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Divider()

            // Ratings
            ForEach(groupedRatings, id: \.domain) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.domain).font(.headline)
                    ForEach(group.entries, id: \.id) { e in
                        HStack(spacing: 8) {
                            Text(e.skillLabel)
                            Spacer()
                            Text("Mid: \(e.midYear?.rawValue ?? "")    End: \(e.endYear?.rawValue ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                Divider()
            }

            // Comments by section
            ForEach(ProgressReportSchema.commentSections, id: \.self) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section).font(.headline)
                    if let mid = report.comments.midYearBySection[section], !mid.isEmpty {
                        Text("Mid-Year:").font(.caption).foregroundStyle(.secondary)
                        Text(mid)
                    }
                    if let end = report.comments.endYearBySection[section], !end.isEmpty {
                        Text("End-of-Year:").font(.caption).foregroundStyle(.secondary)
                        Text(end)
                    }
                }
                Divider()
            }

            // Mid-Year Summary
            VStack(alignment: .leading, spacing: 4) {
                Text("Mid-Year Summary").font(.headline)
                labeledBlock("Overview", report.comments.midYearOverview)
                labeledBlock("Strengths", report.comments.midYearStrengths)
                labeledBlock("Areas for Growth", report.comments.midYearAreasForGrowth)
                labeledBlock("Goals", report.comments.midYearGoals)
                labeledBlock("Outlook", report.comments.midYearOutlook)
            }
            Divider()

            // End-of-Year Narrative
            VStack(alignment: .leading, spacing: 4) {
                Text("End-of-Year Narrative").font(.headline)
                labeledBlock("Overview", report.comments.endYearOverview)
                labeledBlock("Strengths", report.comments.endYearStrengths)
                labeledBlock("Challenges", report.comments.endYearChallenges)
                labeledBlock("Current Strategies and Support", report.comments.endYearCurrentStrategies)
                labeledBlock("Goals", report.comments.endYearGoals)
                labeledBlock("Outlook", report.comments.endYearOutlook)
            }
        }
        .padding(24)
    }

    private func labeledBlock(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(body)
        }
    }
}

#Preview {
    let s = Student(firstName: "Yosef", lastName: "Cohen", birthday: Date(), level: .lower)
    let report = StudentProgressReport(
        studentPersistentID: s.id.uuidString,
        ratings: ProgressReportSchema.defaultEntries(),
        comments: ReportComments()
    )
    ProgressReportPrintView(student: s, report: report)
}
