// ObservationPrompts.swift
// Montessori-specific observation prompt library.
// Non-evaluative prompts guide teachers to observe specific behaviors.

import Foundation

struct ObservationPrompt: Identifiable {
    let id = UUID()
    let question: String
    let category: String
    let suggestedTags: [String]
}

enum ObservationPromptLibrary {
    static let prompts: [ObservationPrompt] = [
        // Concentration
        ObservationPrompt(
            question: "What is the child's level of concentration on this activity?",
            category: "Concentration",
            suggestedTags: [MontessoriObservationTags.concentration]
        ),
        ObservationPrompt(
            question: "How long has the child been engaged without interruption?",
            category: "Concentration",
            suggestedTags: [MontessoriObservationTags.concentration]
        ),

        // Repetition
        ObservationPrompt(
            question: "Is the child repeating the activity? How many times?",
            category: "Repetition",
            suggestedTags: [MontessoriObservationTags.repetition]
        ),
        ObservationPrompt(
            question: "What variations is the child making in the repeated work?",
            category: "Repetition",
            suggestedTags: [MontessoriObservationTags.repetition]
        ),

        // Social Interaction
        ObservationPrompt(
            question: "How is the child interacting with peers during this work?",
            category: "Social",
            suggestedTags: [MontessoriObservationTags.socialInteraction]
        ),
        ObservationPrompt(
            question: "Is the child choosing to work alone or with others?",
            category: "Social",
            suggestedTags: [MontessoriObservationTags.socialInteraction]
        ),

        // Independence
        ObservationPrompt(
            question: "Is the child working independently or seeking assistance?",
            category: "Independence",
            suggestedTags: [MontessoriObservationTags.independence]
        ),
        ObservationPrompt(
            question: "Did the child independently select and prepare this work?",
            category: "Independence",
            suggestedTags: [MontessoriObservationTags.independence]
        ),

        // Material Use
        ObservationPrompt(
            question: "How is the child handling and using the materials?",
            category: "Material Use",
            suggestedTags: [MontessoriObservationTags.materialUse]
        ),
        ObservationPrompt(
            question: "Is the child returning materials to their proper place?",
            category: "Material Use",
            suggestedTags: [MontessoriObservationTags.materialUse, MontessoriObservationTags.loveOfOrder]
        ),

        // Movement
        ObservationPrompt(
            question: "How is the child moving through the environment?",
            category: "Movement",
            suggestedTags: [MontessoriObservationTags.movement]
        ),

        // Normalization
        ObservationPrompt(
            question: "What signs of normalization are you observing?",
            category: "Normalization",
            suggestedTags: [MontessoriObservationTags.normalization]
        ),
        ObservationPrompt(
            question: "Does the child show joy and satisfaction in the work?",
            category: "Normalization",
            suggestedTags: [MontessoriObservationTags.loveOfWork, MontessoriObservationTags.normalization]
        ),

        // Self-Discipline
        ObservationPrompt(
            question: "How does the child respond to distractions in the environment?",
            category: "Self-Discipline",
            suggestedTags: [MontessoriObservationTags.selfDiscipline, MontessoriObservationTags.concentration]
        ),

        // Order
        ObservationPrompt(
            question: "How does the child organize their workspace and materials?",
            category: "Order",
            suggestedTags: [MontessoriObservationTags.loveOfOrder]
        )
    ]
}
