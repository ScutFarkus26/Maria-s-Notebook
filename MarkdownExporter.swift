import SwiftUI
import Foundation

struct MarkdownExporter {
    static func markdown(for t: CommunityTopic) -> String {
        var m = """
        # \(t.title)
        
        """
        let issue = t.issueDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !issue.isEmpty {
            m += """
            **Issue**
            
            \(issue)
            
            """
        }
        if !t.proposedSolutions.isEmpty {
            m += "## Proposed Solutions\n\n"
            for s in t.proposedSolutions {
                let title = s.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let details = s.details.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    m += "- **\(title)**"
                    if !details.isEmpty { m += ": \(details)" }
                    if !s.proposedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { m += " _(by \(s.proposedBy))_" }
                    if s.isAdopted { m += " ✅" }
                    m += "\n"
                } else if !details.isEmpty {
                    m += "- \(details)\n"
                }
            }
            m += "\n"
        }
        let resolution = t.resolution.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolution.isEmpty {
            m += """
            ## Resolution
            
            \(resolution)
            
            """
        }
        if !t.notes.isEmpty {
            m += "## Meeting Notes\n\n"
            let notes = t.notes.sorted { $0.createdAt < $1.createdAt }
            for n in notes {
                let speaker = n.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
                let content = n.content.trimmingCharacters(in: .whitespacesAndNewlines)
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

    #if os(iOS)
    static func presentShare(_ text: String) {
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        UIApplication.shared.windows.first?.rootViewController?.present(av, animated: true)
    }
    #else
    static func presentShare(_ text: String) { }
    #endif
}

