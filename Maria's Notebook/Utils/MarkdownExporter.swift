import SwiftUI
import Foundation
#if os(iOS)
import UIKit
#endif

struct MarkdownExporter {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func markdown(for t: CDCommunityTopicEntity) -> String {
        var m = """
        # \(t.title)
        
        """
        let issue = t.issueDescription.trimmed()
        if !issue.isEmpty {
            m += """
            **Issue**
            
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
        let meetingNotes = (t.unifiedNotes?.allObjects as? [CDNote]) ?? []
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

    #if os(iOS)
    @MainActor
    static func presentShare(_ text: String) {
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
            var top = window.rootViewController
        else { return }
        while let presented = top.presentedViewController { top = presented }
        top.present(av, animated: true)
    }
    #else
    static func presentShare(_ text: String) { }
    #endif
}
