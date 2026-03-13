// MontessoriObservationTags.swift
// Predefined Montessori observation tags using the existing TagHelper system.
// Tags follow the "Name|Color" format for consistency with the note tag system.

import Foundation

enum MontessoriObservationTags {
    // MARK: - Core Observation Tags

    static let concentration = TagHelper.createTag(name: "Concentration", color: .blue)
    static let repetition = TagHelper.createTag(name: "Repetition", color: .green)
    static let socialInteraction = TagHelper.createTag(name: "Social Interaction", color: .purple)
    static let independence = TagHelper.createTag(name: "Independence", color: .blue)
    static let materialUse = TagHelper.createTag(name: "Material Use", color: .orange)
    static let movement = TagHelper.createTag(name: "Movement", color: .green)

    // MARK: - Normalization Indicator Tags

    static let normalization = TagHelper.createTag(name: "Normalization", color: .yellow)
    static let loveOfOrder = TagHelper.createTag(name: "Love of Order", color: .yellow)
    static let loveOfWork = TagHelper.createTag(name: "Love of Work", color: .green)
    static let attachmentToReality = TagHelper.createTag(name: "Attachment to Reality", color: .blue)
    static let selfDiscipline = TagHelper.createTag(name: "Self-Discipline", color: .orange)

    /// All observation tags for the quick-tag bar
    static let allTags: [String] = [
        concentration,
        repetition,
        socialInteraction,
        independence,
        materialUse,
        movement,
        normalization,
        loveOfOrder,
        loveOfWork,
        attachmentToReality,
        selfDiscipline
    ]

    /// Normalization indicator tags specifically (subset of allTags)
    static let normalizationIndicators: [String] = [
        concentration,
        loveOfOrder,
        loveOfWork,
        attachmentToReality,
        selfDiscipline
    ]

    /// Check if a given tag is a Montessori observation tag
    static func isObservationTag(_ tag: String) -> Bool {
        let name = TagHelper.tagName(tag)
        return allTags.contains { TagHelper.tagName($0) == name }
    }
}
