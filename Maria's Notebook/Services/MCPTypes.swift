//
//  MCPTypes.swift
//  Maria's Notebook
//
//  Shared types for MCP integration
//

import Foundation

/// Response structure for MCP student analysis
struct MCPAnalysisResponse: Codable {
    let overallProgress: String
    let keyStrengths: [String]
    let areasForGrowth: [String]
    let developmentalMilestones: [String]
    let observedPatterns: [String]
    let behavioralTrends: [String]
    let socialEmotionalInsights: [String]
    let recommendedNextLessons: [String]
    let suggestedPracticeFocus: [String]
    let interventionSuggestions: [String]
}
