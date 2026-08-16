import Foundation

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

struct ObservationSourcePacket: Identifiable, Sendable {
    let key: String
    let reference: EvidenceReference
    let promptText: String

    var id: String { key }
}

enum ObservationReflectionService {
    static func sourcePackets(
        from items: [UnifiedObservationItem],
        maximumRecords: Int = 40,
        maximumCharacters: Int = 12_000
    ) -> [ObservationSourcePacket] {
        guard maximumRecords > 0, maximumCharacters > 0 else { return [] }

        var remainingCharacters = maximumCharacters
        var packets: [ObservationSourcePacket] = []

        for (index, item) in items.prefix(maximumRecords).enumerated() {
            guard remainingCharacters > 0 else { break }
            let key = "O\(index + 1)"
            let context = item.contextText?.trimmed().isEmpty == false
                ? item.contextText!.trimmed()
                : "Observation"
            let date = DateFormatters.mediumDate.string(from: item.date)
            let prefix = "[\(key)] \(date) | \(context) | "
            let availableForBody = max(0, remainingCharacters - prefix.count)
            guard availableForBody > 0 else { break }
            let body = String(item.body.trimmed().prefix(availableForBody))
            guard !body.isEmpty else { continue }

            let promptText = prefix + body
            remainingCharacters -= promptText.count
            packets.append(ObservationSourcePacket(
                key: key,
                reference: EvidenceReference(
                    entityKind: .note,
                    entityID: item.id,
                    date: item.date,
                    title: context,
                    excerpt: String(body.prefix(180))
                ),
                promptText: promptText
            ))
        }

        return packets
    }

    static func prompt(from packets: [ObservationSourcePacket], narrative: Bool) -> String {
        let sourceText = packets.map(\.promptText).joined(separator: "\n")
        if narrative {
            return """
            Draft one concise narrative paragraph from the records below. Stay factual, avoid diagnosis and readiness judgments, and do not add information. This is an editable draft, not a guide decision.

            \(sourceText)
            """
        }
        return """
        Review the source records below. Return factual observations, repeated patterns worth reviewing, and questions the guide may choose to observe next.

        Every finding must include one or more source keys exactly as written (for example O1). A repeated pattern must cite at least two different records. Do not classify sentiment, diagnose, infer emotion, score readiness, or make a decision for the guide.

        \(sourceText)
        """
    }

    static func referenceMap(from packets: [ObservationSourcePacket]) -> [String: EvidenceReference] {
        Dictionary(uniqueKeysWithValues: packets.map { ($0.key, $0.reference) })
    }

    #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    static func validate(_ digest: NotesDigest, against packets: [ObservationSourcePacket]) -> NotesDigest {
        let validKeys = Set(packets.map(\.key))

        func clean(
            _ findings: [GroundedObservationFinding],
            minimumSources: Int
        ) -> [GroundedObservationFinding] {
            findings.compactMap { finding in
                let keys = Array(Set(finding.sourceKeys.filter { validKeys.contains($0) })).sorted()
                guard keys.count >= minimumSources, !finding.text.trimmed().isEmpty else { return nil }
                return GroundedObservationFinding(text: finding.text.trimmed(), sourceKeys: keys)
            }
        }

        return NotesDigest(
            factualObservations: clean(digest.factualObservations, minimumSources: 1),
            repeatedPatterns: clean(digest.repeatedPatterns, minimumSources: 2),
            questionsToObserveNext: clean(digest.questionsToObserveNext, minimumSources: 1)
        )
    }
    #endif
}
