// ProgressReportSchema.swift
// Defines the default schema that matches the school's template exactly.

import Foundation

public enum ProgressReportSchema {
    public static func defaultEntries() -> [ReportRatingEntry] {
        var entries: [ReportRatingEntry] = []
        func add(_ id: String, _ domain: String, _ label: String) { entries.append(ReportRatingEntry(id: id, domain: domain, skillLabel: label)) }

        // Judaics / Hebrew
        // Kriah

        // Chumash

        // Kesivah

        // Taryag Mitzvos

        // Navi / Yamim Tovim

        // General Studies
        // ELA (subset representative; extend with exact list as template requires)
        add("ela_reads_fluently_expression", "ELA", "Reads fluently with expression")
        add("ela_retells_plot_setting_characters", "ELA", "Retells plot, setting, and characters")
        add("ela_self_monitoring", "ELA", "Self-monitoring while reading")
        add("ela_makes_connections", "ELA", "Makes connections")
        add("ela_sensory_imaging", "ELA", "Sensory imaging")
        add("ela_questioning", "ELA", "Questioning")
        add("ela_inference", "ELA", "Inference")
        add("ela_synthesizing", "ELA", "Synthesizing")

        // Math
        add("math_numbers_operations", "Math", "Numbers and Operations")
        add("math_speed", "Math", "Math Speed")
        add("math_problem_solving", "Math", "Problem Solving")
        add("math_multiples_factors", "Math", "Multiples & Factors")
        add("math_squares_cubes", "Math", "Squares & Cubes")
        add("math_fractions", "Math", "Fractions")
        add("math_decimals", "Math", "Decimals")
        add("math_measurement", "Math", "Measurement")
        add("math_graphing_data", "Math", "Graphing & Data")
        add("math_geometry", "Math", "Geometry")
        add("math_pre_algebra_algebra", "Math", "Pre-Algebra and Algebra")

        // History / Geography / Biomes
        add("history_understands_general_concepts", "History/Geography/Biomes", "Understands General Concepts")

        // Science
        add("science_understands_general_concepts", "Science", "Understands General Concepts")

        // Behavior / Work Habits
        add("behavior_courteous", "Behavior/Work Habits", "Courteous")
        add("behavior_organized", "Behavior/Work Habits", "Organized")
        add("behavior_neat_pride", "Behavior/Work Habits", "Neat/pride")
        add("behavior_works_independently", "Behavior/Work Habits", "Works independently")
        add("behavior_works_cooperatively", "Behavior/Work Habits", "Works cooperatively")
        add("behavior_effort", "Behavior/Work Habits", "Effort")
        add("behavior_listens_attentively", "Behavior/Work Habits", "Listens attentively")
        add("behavior_respectful", "Behavior/Work Habits", "Respectful")
        add("behavior_participates_group_discussions", "Behavior/Work Habits", "Participates in group discussions")

        return entries
    }

    public static let commentSections: [String] = [
        "ELA", "Math", "Behavior/Work Habits",
        "History/Geography/Biomes", "Science"
    ]
}
