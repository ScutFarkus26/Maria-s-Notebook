// LessonPlanningService+ResponseParsing.swift
// Private JSON parsing helpers for LessonPlanningService.

import Foundation
import OSLog

extension LessonPlanningService {

    // MARK: - Response Parsing

    func parseRecommendations(
        from jsonString: String,
        students: [CDStudent],
        profiles: [StudentReadinessProfile] = []
    ) -> [LessonRecommendation] {
        guard let data = jsonString.data(using: .utf8) else { return [] }

        do {
            let response = try JSONDecoder().decode(PlanningResponse.self, from: data)
            let allLessons = fetchAllLessons()

            return response.recommendations.compactMap { apiRec in
                // Resolve lesson ID from name
                let lesson = allLessons.first { $0.name.lowercased() == apiRec.lessonName.lowercased() }
                    ?? allLessons.first { $0.name.lowercased().contains(apiRec.lessonName.lowercased()) }

                guard let lessonID = lesson?.id else {
                    Self.logger.info("Could not resolve lesson: \(apiRec.lessonName)")
                    return nil
                }

                // Resolve student IDs from names
                let resolvedStudentIDs = apiRec.studentNames.compactMap { name -> UUID? in
                    resolveStudentID(named: name, from: students)
                }
                let evidenceAvailability = evidenceAvailability(
                    for: lessonID,
                    studentIDs: resolvedStudentIDs,
                    profiles: profiles
                )

                return LessonRecommendation(
                    lessonID: lessonID,
                    lessonName: lesson?.name ?? apiRec.lessonName,
                    area: apiRec.area,
                    sequence: apiRec.sequence,
                    studentIDs: resolvedStudentIDs,
                    studentNames: apiRec.studentNames,
                    reasoning: apiRec.reasoning,
                    confidence: apiRec.confidence ?? 0,
                    evidenceAvailability: evidenceAvailability,
                    priority: apiRec.priority,
                    suggestedDay: apiRec.suggestedDay
                )
            }
        } catch {
            Self.logger.warning("Failed to parse planning response: \(error)")
            return []
        }
    }

    /// Resolve only unambiguous names from the supplied classroom roster. This
    /// avoids silently attaching evidence to the wrong child when first names repeat.
    private func resolveStudentID(named name: String, from students: [CDStudent]) -> UUID? {
        let normalized = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = students.filter { student in
            let candidates = [student.fullName, student.firstName, student.nickname ?? ""]
                .filter { !$0.isEmpty }
                .map {
                    $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            return candidates.contains(normalized)
        }
        guard matches.count == 1 else { return nil }
        return matches[0].id
    }

    /// Evidence availability is computed from local profiles, never from model
    /// confidence. For a group, the least-supported student determines the label.
    private func evidenceAvailability(
        for lessonID: UUID,
        studentIDs: [UUID],
        profiles: [StudentReadinessProfile]
    ) -> EvidenceAvailability {
        let values = studentIDs.map { studentID -> EvidenceAvailability in
            guard let profile = profiles.first(where: { $0.studentID == studentID }) else {
                return .insufficient
            }
            let matchingAreas = profile.areaReadiness.filter {
                $0.nextLessonID == lessonID || $0.currentLessonID == lessonID
            }
            return EvidenceAvailability.combined(matchingAreas.map(\.evidenceAvailability))
        }
        return EvidenceAvailability.combined(values)
    }

    func parseGroupings(from jsonString: String, students: [CDStudent]) -> [GroupingSuggestion] {
        guard let data = jsonString.data(using: .utf8) else { return [] }

        do {
            let response = try JSONDecoder().decode(PlanningResponse.self, from: data)
            let allLessons = fetchAllLessons()
            let studentNameMap = Dictionary(uniqueKeysWithValues: students.compactMap { student -> (String, UUID)? in
                guard let id = student.id else { return nil }
                return (student.fullName.lowercased(), id)
            })

            return (response.groupingSuggestions ?? []).compactMap { apiGroup in
                let lesson = allLessons.first { $0.name.lowercased() == apiGroup.lessonName.lowercased() }
                guard let lessonID = lesson?.id else { return nil }

                let studentIDs = apiGroup.studentNames.compactMap { name -> UUID? in
                    studentNameMap[name.lowercased()]
                }

                return GroupingSuggestion(
                    lessonID: lessonID,
                    lessonName: lesson?.name ?? apiGroup.lessonName,
                    studentIDs: studentIDs,
                    studentNames: apiGroup.studentNames,
                    rationale: apiGroup.rationale
                )
            }
        } catch {
            return []
        }
    }

    func parseSummary(from jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8) else { return "" }

        do {
            let response = try JSONDecoder().decode(PlanningResponse.self, from: data)
            return response.summary ?? "Plan generated."
        } catch {
            return jsonString.prefix(500).description
        }
    }
}
