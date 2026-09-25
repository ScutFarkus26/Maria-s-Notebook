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
        static let doc = "doc"
        static let docText = "doc.text"
        static let folder = "folder"
        static let folderFill = "folder.fill"
        static let folderBadgePlus = "folder.badge.plus"
        static let link = "link"
    }
    
    // MARK: - Communication
    enum Communication {
        static let envelope = "envelope"
        static let message = "message"
    }
    
    // MARK: - Time & Calendar
    enum Time {
        static let calendar = "calendar"
        static let calendarBadgePlus = "calendar.badge.plus"
        static let clock = "clock"
        static let timer = "timer"
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
        static let note = "note"
        static let noteText = "note.text"
    }
    
    // MARK: - Status & Indicators
    enum Status {
        static let exclamationmarkTriangleFill = "exclamationmark.triangle.fill"
        static let info = "info"
    }

    // MARK: - Search & Filter
    enum Search {
        static let magnifyingglass = "magnifyingglass"
        static let lineHorizontal3DecreaseCircle = "line.3.horizontal.decrease.circle"
    }
    
    // MARK: - Settings & Preferences
    enum Settings {
        static let gear = "gear"
        static let gearshape = "gearshape"
        static let togglepower = "togglepower"
    }
    
    // MARK: - Lists & Organization
    enum List {
        static let list = "list.bullet"
        static let checklist = "checklist"
        static let squareGrid = "square.grid.2x2"
    }
    
    // MARK: - Arrows & Directions
    enum Arrow {
        static let up = "arrow.up"
        static let down = "arrow.down"
        static let left = "arrow.left"
        static let right = "arrow.right"
        static let upCircleFill = "arrow.up.circle.fill"
    }
    
    // MARK: - Shapes & Containers
    enum Shape {
        static let star = "star"
        static let starFill = "star.fill"
    }
    
    // MARK: - Data & Storage
    enum Data {
        static let icloud = "icloud"
        static let externaldrive = "externaldrive"
        static let internaldrive = "internaldrive"
        static let server = "server.rack"
    }
    
    // MARK: - Favorites & Ratings
    enum Rating {
        static let star = "star"
        static let starFill = "star.fill"
        static let flag = "flag"
    }
    
    // MARK: - Editing & Tools
    enum Tool {
        static let pencil = "pencil"
        static let wand = "wand.and.stars"
    }
    
    // MARK: - Numbers & Text
    enum Text {
        static let textformat = "textformat"
        static let bold = "bold"
        static let italic = "italic"
        static let underline = "underline"
        static let strikethrough = "strikethrough"
        static let textAlignLeft = "text.alignleft"
    }
    
    // MARK: - System & Hardware
    enum System {
        static let desktopcomputer = "desktopcomputer"
        static let laptopcomputer = "laptopcomputer"
        static let iphone = "iphone"
        static let ipad = "ipad"
        static let keyboard = "keyboard"
        static let printer = "printer"
        static let scanner = "scanner"
    }
    
    // MARK: - Charts & Data Visualization
    enum Chart {
        static let chartLine = "chart.line.uptrend.xyaxis"
    }
}
