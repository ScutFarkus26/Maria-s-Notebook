// DevelopmentalCharacteristicsTags.swift
// Second-plane developmental characteristics for elementary Montessori observation.
// Tags use the existing TagHelper system for consistency with the CDNote tag infrastructure.

import Foundation
import SwiftUI

enum DevelopmentalCharacteristic: String, CaseIterable, Identifiable {
    case reasoningMind = "Reasoning Mind"
    case moralSense = "Moral Sense"
    case imagination = "Imagination"
    case socialInstinct = "Social Instinct"
    case heroWorship = "Hero Worship"
    case goingOutInstinct = "Going-Out Instinct"
    case bigWork = "Big Work"
    case justice = "Justice & Fairness"

    var id: String { rawValue }

    /// Tag string in "Name|Color" format for use with the CDNote tag system
    var tag: String {
        switch self {
        case .reasoningMind:
            return TagHelper.createTag(name: rawValue, color: .purple)
        case .moralSense:
            return TagHelper.createTag(name: rawValue, color: .orange)
        case .imagination:
            return TagHelper.createTag(name: rawValue, color: .pink)
        case .socialInstinct:
            return TagHelper.createTag(name: rawValue, color: .green)
        case .heroWorship:
            return TagHelper.createTag(name: rawValue, color: .yellow)
        case .goingOutInstinct:
            return TagHelper.createTag(name: rawValue, color: .blue)
        case .bigWork:
            return TagHelper.createTag(name: rawValue, color: .red)
        case .justice:
            return TagHelper.createTag(name: rawValue, color: .orange)
        }
    }

    /// SF Symbol icon for display
    var icon: String {
        switch self {
        case .reasoningMind: return "brain.head.profile"
        case .moralSense: return "heart.circle"
        case .imagination: return "sparkles"
        case .socialInstinct: return "person.2"
        case .heroWorship: return "star.circle"
        case .goingOutInstinct: return "figure.walk"
        case .bigWork: return "hammer"
        case .justice: return "scale.3d"
        }
    }

    /// Brief pedagogical description
    var description: String {
        switch self {
        case .reasoningMind:
            return "The child reasons about cause and effect, asks 'why' and 'how'"
        case .moralSense:
            return "The child distinguishes right from wrong, develops conscience"
        case .imagination:
            return "The child uses imagination to explore what cannot be directly experienced"
        case .socialInstinct:
            return "The child seeks group belonging, collaborative work, and peer relationships"
        case .heroWorship:
            return "The child admires heroes and role models, seeks inspiration"
        case .goingOutInstinct:
            return "The child desires to explore beyond the classroom into the larger world"
        case .bigWork:
            return "The child undertakes large, sustained projects requiring planning and effort"
        case .justice:
            return "The child develops a strong sense of fairness and equity"
        }
    }

    /// Tag color for display
    var color: Color {
        TagHelper.tagColor(tag).color
    }

    /// All developmental characteristic tags
    static var allTags: [String] {
        allCases.map(\.tag)
    }

    /// Check if a tag is a developmental characteristic tag
    static func isCharacteristicTag(_ tag: String) -> Bool {
        let name = TagHelper.tagName(tag)
        return allCases.contains { $0.rawValue == name }
    }

    /// Find characteristic from tag string
    static func from(tag: String) -> DevelopmentalCharacteristic? {
        let name = TagHelper.tagName(tag)
        return allCases.first { $0.rawValue == name }
    }
}
