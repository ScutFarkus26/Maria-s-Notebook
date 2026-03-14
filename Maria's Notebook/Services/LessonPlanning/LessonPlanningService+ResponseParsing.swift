// LessonPlanningService+ResponseParsing.swift
// Private JSON parsing helpers for LessonPlanningService.

import Foundation
import OSLog

extension LessonPlanningService {

    // MARK: - Response Parsing

    func parseRecommendations(from jsonString: String, students: [Student]) -> [LessonRecommendation] {
        guard let data = jsonString.data(using: .utf8) else { return [] }

        do {
            let response = try JSONDecoder().decode(PlanningResponse.self, from: data)
            let allLessons = fetchAllLessons()
            let studentNameMap = Dictionary(uniqueKeysWithValues: students.map { ($0.fullName.lowercased(), $0.id) })

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
                    let lowered = name.lowercased()
                    let firstWord = lowered.components(separatedBy: " ").first ?? ""
                    return studentNameMap[lowered]
                        ?? studentNameMap.first { $0.key.contains(firstWord) }?.value
                }

                return LessonRecommendation(
                    lessonID: lessonID,
                    lessonName: lesson?.name ?? apiRec.lessonName,
                    subject: apiRec.subject,
                    group: apiRec.group,
                    studentIDs: resolvedStudentIDs,
                    studentNames: apiRec.studentNames,
                    reasoning: apiRec.reasoning,
                    confidence: apiRec.confidence,
                    priority: apiRec.priority,
                    suggestedDay: apiRec.suggestedDay
                )
            }
        } catch {
            Self.logger.warning("Failed to parse planning response: \(error)")
            return []
        }
    }

    func parseGroupings(from jsonString: String, students: [Student]) -> [GroupingSuggestion] {
        guard let data = jsonString.data(using: .utf8) else { return [] }

        do {
            let response = try JSONDecoder().decode(PlanningResponse.self, from: data)
            let allLessons = fetchAllLessons()
            let studentNameMap = Dictionary(uniqueKeysWithValues: students.map { ($0.fullName.lowercased(), $0.id) })

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
