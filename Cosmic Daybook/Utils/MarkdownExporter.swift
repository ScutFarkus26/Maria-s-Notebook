import Foundation

struct MarkdownExporter {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func markdown(for t: CDCommunityTopicEntity) -> String {
        var m = """
        # \(t.title)
        
        """
        let issue = t.issueDescription.trimmed()
        if !issue.isEmpty {
            m += """
            **CDIssue**
            
            \(issue)
            
            """
        }
        let solutions = (t.proposedSolutions?.allObjects as? [CDProposedSolutionEntity]) ?? []
        if !solutions.isEmpty {
            m += "## Proposed Solutions\n\n"
            for s in solutions {
                let title = s.title.trimmed()
                let details = s.details.trimmed()
                if !title.isEmpty {
                    m += "- **\(title)**"
                    if !details.isEmpty { m += ": \(details)" }
                    if !s.proposedBy.trimmed().isEmpty { m += " _(by \(s.proposedBy))_" }
                    if s.isAdopted { m += " ✅" }
                    m += "\n"
                } else if !details.isEmpty {
                    m += "- \(details)\n"
                }
            }
            m += "\n"
        }
        let resolution = t.resolution.trimmed()
        if !resolution.isEmpty {
            m += """
            ## Resolution
            
            \(resolution)
            
            """
        }
        let meetingNotes = t.unifiedNotes
        if !meetingNotes.isEmpty {
            m += "## Meeting Notes\n\n"
            let notes = meetingNotes.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            for n in notes {
                let speaker = (n.reporterName ?? "").trimmed()
                let content = n.body.trimmed()
                if !content.isEmpty {
                    if speaker.isEmpty {
                        m += "- \(content)\n"
                    } else {
                        m += "- **\(speaker):** \(content)\n"
                    }
                }
            }
            m += "\n"
        }
        return m
    }
}
