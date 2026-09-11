//
//  MCPNotebookTools+PresentationSchema.swift
//  Maria's Notebook
//
//  The argument shape of record_presentation — one presentation's fields,
//  reused verbatim for each item of the `presentations` batch — and the
//  follow_up vocabulary mapped onto the capture review's own outcomes.
//

import Foundation

extension MCPNotebookTools {

    static let recordPresentationSchema: JSONValue = {
        var properties = presentationProperties
        properties["presentations"] = [
            "type": "array",
            "description": .string("Several presentations in one call, each with the fields above "
                + "(lesson, student_names, date, group_observation, student_observations)"),
            "items": [
                "type": "object",
                "properties": .object(presentationProperties),
                "required": ["lesson", "student_names"]
            ]
        ]
        return .object(["type": "object", "properties": .object(properties)])
    }()

    /// The fields one presentation takes, shared by the single form and each
    /// item of `presentations`.
    private static let presentationProperties: [String: JSONValue] = [
        "lesson": [
            "type": "string",
            "description": "The lesson presented: a lesson id from find_lessons, or its exact name"
        ],
        "student_names": [
            "type": "array",
            "items": ["type": "string"],
            "minItems": 1,
            "description": "The students the lesson was given to: first names, full names, or nicknames"
        ],
        "date": [
            "type": "string",
            "description": "The day it was presented, YYYY-MM-DD (default today)"
        ],
        "group_observation": [
            "type": "string",
            "description": .string("What happened in the presentation as a whole — "
                + "the part that is about the group, not one child")
        ],
        "student_observations": [
            "type": "array",
            "description": "What the guide noticed about individual children, and what they decided next",
            "items": [
                "type": "object",
                "properties": [
                    "student": [
                        "type": "string",
                        "description": "One of the students named in student_names"
                    ],
                    "observation": [
                        "type": "string",
                        "description": "The observation, as the guide phrased it"
                    ],
                    "follow_up": [
                        "type": "string",
                        "enum": .array(FollowUpArgument.allCases.map { .string($0.rawValue) }),
                        "description": .string("The guide's decision for this child: practice (a practice work "
                            + "item), follow_up_work (a follow-up work item, titled from follow_up_detail), "
                            + "re_present (the lesson goes back on her planning list), ready_for_next_lesson "
                            + "(confirms her on the presentation), continue_observing (flags the observation "
                            + "for the follow-up inbox). Omit when the guide made no decision.")
                    ],
                    "follow_up_detail": [
                        "type": "string",
                        "description": "For practice or follow_up_work: the work's title, if the guide named one"
                    ],
                    "needs_follow_up": [
                        "type": "boolean",
                        "description": "Flag this observation for the follow-up inbox (same as continue_observing)"
                    ]
                ],
                "required": ["student", "observation"]
            ]
        ]
    ]

    /// The `follow_up` argument's vocabulary, mapped onto the capture review's
    /// own outcomes so the same rows are written either way.
    enum FollowUpArgument: String, CaseIterable {
        case practice
        case followUpWork = "follow_up_work"
        case rePresent = "re_present"
        case readyForNextLesson = "ready_for_next_lesson"
        case continueObserving = "continue_observing"

        var outcome: CaptureFollowUp {
            switch self {
            case .practice: return .practice
            case .followUpWork: return .followUpWork
            case .rePresent: return .represent
            case .readyForNextLesson: return .readyForNextLesson
            case .continueObserving: return .continueObserving
            }
        }
    }
}
