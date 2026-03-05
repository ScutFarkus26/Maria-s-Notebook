import SwiftUI
import Foundation
#if os(iOS)
import UIKit
#endif

struct MarkdownExporter {
    static func markdown(for t: CommunityTopic) -> String {
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
        if !(t.proposedSolutions ?? []).isEmpty {
            m += "## Proposed Solutions\n\n"
            for s in t.proposedSolutions ?? [] {
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
        if !(t.unifiedNotes ?? []).isEmpty {
            m += "## Meeting Notes\n\n"
            let notes = (t.unifiedNotes ?? []).sorted { $0.createdAt < $1.createdAt }
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
