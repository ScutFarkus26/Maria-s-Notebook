import Foundation

// Centralized SF Symbol names for type-safe icon usage throughout the app
// Eliminates string literal typos and provides autocomplete support
enum SFSymbol {
    // MARK: - Navigation
    enum Navigation {
        static let chevronDown = "chevron.down"
        static let chevronUp = "chevron.up"
    }
    
    // MARK: - Actions
    enum Action {
        static let plus = "plus"
        static let plusCircle = "plus.circle"
        static let plusCircleFill = "plus.circle.fill"
        static let xmark = "xmark"
        static let xmarkCircleFill = "xmark.circle.fill"
        static let checkmark = "checkmark"
        static let checkmarkCircle = "checkmark.circle"
        static let checkmarkCircleFill = "checkmark.circle.fill"
        static let trash = "trash"
        static let arrowClockwise = "arrow.clockwise"
        static let arrowCounterclockwise = "arrow.counterclockwise"
    }
    
    // MARK: - Documents & Files
    enum CDDocument {
        static let docText = "doc.text"
        static let folder = "folder"
        static let folderFill = "folder.fill"
        static let folderBadgePlus = "folder.badge.plus"
    }
    
    // MARK: - Communication
    enum Communication {
        static let envelope = "envelope"
    }
    
    // MARK: - Time & Calendar
    enum Time {
        static let calendar = "calendar"
        static let calendarBadgePlus = "calendar.badge.plus"
        static let clock = "clock"
    }
    
    // MARK: - People & Social
    enum People {
        static let person = "person"
        static let personFill = "person.fill"
        static let person2 = "person.2"
        static let person3Fill = "person.3.fill"
    }
    
    // MARK: - Education & Learning
    enum Education {
        static let book = "book"
        static let bookFill = "book.fill"
        static let bookClosed = "book.closed"
        static let bookClosedFill = "book.closed.fill"
        static let graduationcap = "graduationcap"
        static let pencil = "pencil"
    }
    
    // MARK: - Status & Indicators
    enum Status {
        static let exclamationmarkTriangleFill = "exclamationmark.triangle.fill"
    }

    // MARK: - Search & Filter
    enum Search {
        static let magnifyingglass = "magnifyingglass"
        static let lineHorizontal3DecreaseCircle = "line.3.horizontal.decrease.circle"
    }
    
    // MARK: - Lists & Organization
    enum List {
        static let list = "list.bullet"
        static let checklist = "checklist"
        static let squareGrid = "square.grid.2x2"
    }
    
    // MARK: - Arrows & Directions
    enum Arrow {
        static let right = "arrow.right"
        static let upCircleFill = "arrow.up.circle.fill"
    }
    
    // MARK: - Shapes & Containers
    enum Shape {
        static let star = "star"
        static let starFill = "star.fill"
    }
    
    // MARK: - Favorites & Ratings
    enum Rating {
        static let flag = "flag"
    }
    
    // MARK: - Editing & Tools
    enum Tool {
        static let wand = "wand.and.stars"
    }
    
    // MARK: - Numbers & Text
    enum Text {
        static let textformat = "textformat"
        static let textAlignLeft = "text.alignleft"
    }
    
    // MARK: - Charts & Data Visualization
    enum Chart {
        static let chartLine = "chart.line.uptrend.xyaxis"
    }
}
