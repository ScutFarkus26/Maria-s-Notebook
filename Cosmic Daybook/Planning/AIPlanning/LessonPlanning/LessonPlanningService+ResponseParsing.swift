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

            let candidates = allLessons.compactMap { lesson -> LessonData? in
                guard let id = lesson.id else { return nil }
                return LessonData(id: id, name: lesson.name, area: lesson.area, sequence: lesson.sequence)
            }

            return response.recommendations.compactMap { apiRec in
                let lessonID = Self.resolveLessonID(
                    named: apiRec.lessonName, area: apiRec.area, sequence: apiRec.sequence, in: candidates
                )
                let lesson = lessonID.flatMap { id in allLessons.first { $0.id == id } }

                guard let lessonID else {
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

    /// Finds the lesson a suggestion names. Lesson names repeat across areas
    /// ("Introduction", "Addition"), so among lessons with that name the one in
    /// the suggested area and sequence wins, then one in the suggested area,
    /// then the first in curriculum order. Only when no name matches exactly
    /// does a lesson whose name contains the suggested one count, looked for in
    /// the same order.
    nonisolated static func resolveLessonID(
        named name: String,
        area: String,
        sequence: String,
        in lessons: [LessonData]
    ) -> UUID? {
        let wanted = name.folded()
        guard !wanted.isEmpty else { return nil }
        let wantedArea = area.folded()
        let wantedSequence = sequence.folded()

        func best(_ matches: [LessonData]) -> LessonData? {
            let inArea = matches.filter { !wantedArea.isEmpty && $0.area.folded() == wantedArea }
            let inSequence = inArea.filter { !wantedSequence.isEmpty && $0.sequence.folded() == wantedSequence }
            return inSequence.first ?? inArea.first ?? matches.first
        }

        let exact = lessons.filter { $0.name.folded() == wanted }
        if let match = best(exact) { return match.id }
        return best(lessons.filter { $0.name.folded().contains(wanted) })?.id
    }

    /// Resolve only unambiguous names from the supplied classroom roster. This
    /// avoids silently attaching evidence to the wrong child when first names repeat.
    private func resolveStudentID(named name: String, from students: [CDStudent]) -> UUID? {
        let normalized = name.folded()
        let matches = students.filter { student in
            let candidates = [student.fullName, student.firstName, student.nickname ?? ""]
                .filter { !$0.isEmpty }
                .map { $0.folded() }
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

    func parseSummary(from jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8) else { return "" }

        do {
            let response = try JSONDecoder().decode(PlanningResponse.self, from: data)
            return response.summary ?? "Here's a plan."
        } catch {
            return jsonString.prefix(500).description
        }
    }
}
