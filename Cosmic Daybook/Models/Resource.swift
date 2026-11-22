import Foundation

// MARK: - ResourceCategory

enum ResourceCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case writingPapers = "Writing Papers"
    case printableMaterials = "Printable Materials"
    case curriculumGuides = "Curriculum Guides"
    case referenceCharts = "Reference Charts"
    case formsTemplates = "Forms & Templates"
    case assessmentTools = "Assessment Tools"
    case parentCommunication = "Parent Communication"
    case practicalLife = "Practical Life"
    case sensorial = "Sensorial"
    case math = "Math"
    case language = "Language"
    case science = "Science"
    case geography = "Geography"
    case art = "Art"
    case music = "Music"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .writingPapers: return "doc.richtext"
        case .printableMaterials: return "printer"
        case .curriculumGuides: return "book"
        case .referenceCharts: return "chart.bar.doc.horizontal"
        case .formsTemplates: return "doc.on.clipboard"
        case .assessmentTools: return "checkmark.seal"
        case .parentCommunication: return "envelope"
        case .practicalLife: return "hands.sparkles"
        case .sensorial: return "hand.point.up.braille"
        case .math: return "number"
        case .language: return "textformat.abc"
        case .science: return "leaf"
        case .geography: return "globe.americas"
        case .art: return "paintpalette"
        case .music: return "music.note"
        case .other: return "doc"
        }
    }
}
