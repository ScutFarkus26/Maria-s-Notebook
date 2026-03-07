import Foundation

// Centralized SF Symbol names for type-safe icon usage throughout the app
// Eliminates string literal typos and provides autocomplete support
// swiftlint:disable:next type_body_length
enum SFSymbol {
    // MARK: - Navigation
    enum Navigation {
        static let chevronLeft = "chevron.left"
        static let chevronRight = "chevron.right"
        static let chevronDown = "chevron.down"
        static let chevronUp = "chevron.up"
        static let chevronBackward = "chevron.backward"
        static let chevronForward = "chevron.forward"
    }
    
    // MARK: - Actions
    enum Action {
        static let plus = "plus"
        static let plusCircle = "plus.circle"
        static let plusCircleFill = "plus.circle.fill"
        static let minus = "minus"
        static let minusCircle = "minus.circle"
        static let minusCircleFill = "minus.circle.fill"
        static let xmark = "xmark"
        static let xmarkCircle = "xmark.circle"
        static let xmarkCircleFill = "xmark.circle.fill"
        static let checkmark = "checkmark"
        static let checkmarkCircle = "checkmark.circle"
        static let checkmarkCircleFill = "checkmark.circle.fill"
        static let trash = "trash"
        static let trashFill = "trash.fill"
        static let arrowClockwise = "arrow.clockwise"
        static let arrowCounterclockwise = "arrow.counterclockwise"
    }
    
    // MARK: - Documents & Files
    enum Document {
        static let doc = "doc"
        static let docFill = "doc.fill"
        static let docText = "doc.text"
        static let docTextFill = "doc.text.fill"
        static let folder = "folder"
        static let folderFill = "folder.fill"
        static let folderBadgePlus = "folder.badge.plus"
        static let paperclip = "paperclip"
        static let link = "link"
        static let archivebox = "archivebox"
        static let archiveboxFill = "archivebox.fill"
        static let tray = "tray"
        static let trayFill = "tray.fill"
    }
    
    // MARK: - Communication
    enum Communication {
        static let envelope = "envelope"
        static let envelopeFill = "envelope.fill"
        static let envelopeOpen = "envelope.open"
        static let envelopeOpenFill = "envelope.open.fill"
        static let message = "message"
        static let messageFill = "message.fill"
        static let phone = "phone"
        static let phoneFill = "phone.fill"
        static let bubble = "bubble"
        static let bubbleFill = "bubble.fill"
        static let bubbleLeft = "bubble.left"
        static let bubbleLeftFill = "bubble.left.fill"
    }
    
    // MARK: - Time & Calendar
    enum Time {
        static let calendar = "calendar"
        static let calendarBadgePlus = "calendar.badge.plus"
        static let clock = "clock"
        static let clockFill = "clock.fill"
        static let timer = "timer"
        static let stopwatch = "stopwatch"
        static let hourglass = "hourglass"
    }
    
    // MARK: - People & Social
    enum People {
        static let person = "person"
        static let personFill = "person.fill"
        static let personCircle = "person.circle"
        static let personCircleFill = "person.circle.fill"
        static let person2 = "person.2"
        static let person2Fill = "person.2.fill"
        static let person3 = "person.3"
        static let person3Fill = "person.3.fill"
    }
    
    // MARK: - Education & Learning
    enum Education {
        static let book = "book"
        static let bookFill = "book.fill"
        static let bookClosed = "book.closed"
        static let bookClosedFill = "book.closed.fill"
        static let books = "books.vertical"
        static let booksFill = "books.vertical.fill"
        static let graduationcap = "graduationcap"
        static let graduationcapFill = "graduationcap.fill"
        static let pencil = "pencil"
        static let pencilCircle = "pencil.circle"
        static let pencilCircleFill = "pencil.circle.fill"
        static let note = "note"
        static let noteText = "note.text"
        static let backpack = "backpack"
        static let backpackFill = "backpack.fill"
    }
    
    // MARK: - Status & Indicators
    enum Status {
        static let circle = "circle"
        static let circleFill = "circle.fill"
        static let circleInsetFilled = "circle.inset.filled"
        static let dotCircle = "dot.circle"
        static let dotCircleFill = "dot.circle.fill"
        static let exclamationmark = "exclamationmark"
        static let exclamationmarkTriangle = "exclamationmark.triangle"
        static let exclamationmarkTriangleFill = "exclamationmark.triangle.fill"
        static let questionmark = "questionmark"
        static let questionmarkCircle = "questionmark.circle"
        static let questionmarkCircleFill = "questionmark.circle.fill"
        static let info = "info"
        static let infoCircle = "info.circle"
        static let infoCircleFill = "info.circle.fill"
    }
    
    // MARK: - Media & Content
    enum Media {
        static let photo = "photo"
        static let photoFill = "photo.fill"
        static let camera = "camera"
        static let cameraFill = "camera.fill"
        static let video = "video"
        static let videoFill = "video.fill"
        static let play = "play"
        static let playFill = "play.fill"
        static let pause = "pause"
        static let pauseFill = "pause.fill"
        static let mic = "mic"
        static let micFill = "mic.fill"
    }
    
    // MARK: - Search & Filter
    enum Search {
        static let magnifyingglass = "magnifyingglass"
        static let magnifyingglassCircle = "magnifyingglass.circle"
        static let lineHorizontal3Decrease = "line.3.horizontal.decrease"
        static let lineHorizontal3DecreaseCircle = "line.3.horizontal.decrease.circle"
        static let slider = "slider.horizontal.3"
    }
    
    // MARK: - Settings & Preferences
    enum Settings {
        static let gear = "gear"
        static let gearshape = "gearshape"
        static let gearshapeFill = "gearshape.fill"
        static let sliderHorizontal3 = "slider.horizontal.3"
        static let switch2 = "switch.2"
        static let togglepower = "togglepower"
    }
    
    // MARK: - Lists & Organization
    enum List {
        static let list = "list.bullet"
        static let listDash = "list.dash"
        static let listNumber = "list.number"
        static let listStar = "list.star"
        static let listBulletIndent = "list.bullet.indent"
        static let checklist = "checklist"
        static let checklistChecked = "checklist.checked"
        static let squareGrid = "square.grid.2x2"
        static let squareGrid3x3 = "square.grid.3x3"
    }
    
    // MARK: - Arrows & Directions
    enum Arrow {
        static let up = "arrow.up"
        static let down = "arrow.down"
        static let left = "arrow.left"
        static let right = "arrow.right"
        static let upCircle = "arrow.up.circle"
        static let downCircle = "arrow.down.circle"
        static let upCircleFill = "arrow.up.circle.fill"
        static let downCircleFill = "arrow.down.circle.fill"
        static let triangleUp = "arrowtriangle.up"
        static let triangleDown = "arrowtriangle.down"
        static let triangleUpFill = "arrowtriangle.up.fill"
        static let triangleDownFill = "arrowtriangle.down.fill"
    }
    
    // MARK: - Shapes & Containers
    enum Shape {
        static let square = "square"
        static let squareFill = "square.fill"
        static let rectangle = "rectangle"
        static let rectangleFill = "rectangle.fill"
        static let circle = "circle"
        static let circleFill = "circle.fill"
        static let capsule = "capsule"
        static let capsuleFill = "capsule.fill"
        static let star = "star"
        static let starFill = "star.fill"
        static let heart = "heart"
        static let heartFill = "heart.fill"
    }
    
    // MARK: - Data & Storage
    enum Data {
        static let icloud = "icloud"
        static let icloudFill = "icloud.fill"
        static let icloudAndArrowDown = "icloud.and.arrow.down"
        static let icloudAndArrowUp = "icloud.and.arrow.up"
        static let externaldrive = "externaldrive"
        static let externaldriveFill = "externaldrive.fill"
        static let internaldrive = "internaldrive"
        static let server = "server.rack"
    }
    
    // MARK: - Location & Travel
    enum Location {
        static let mappin = "mappin"
        static let mappinCircle = "mappin.circle"
        static let mappinCircleFill = "mappin.circle.fill"
        static let location = "location"
        static let locationFill = "location.fill"
        static let house = "house"
        static let houseFill = "house.fill"
    }
    
    // MARK: - Favorites & Ratings
    enum Rating {
        static let star = "star"
        static let starFill = "star.fill"
        static let starLeading = "star.leadinghalf.filled"
        static let heart = "heart"
        static let heartFill = "heart.fill"
        static let flag = "flag"
        static let flagFill = "flag.fill"
    }
    
    // MARK: - Editing & Tools
    enum Tool {
        static let pencil = "pencil"
        static let pencilCircle = "pencil.circle"
        static let pencilTip = "pencil.tip"
        static let pencilTipCrop = "pencil.tip.crop.circle"
        static let scribble = "scribble"
        static let lasso = "lasso"
        static let paintbrush = "paintbrush"
        static let paintbrushFill = "paintbrush.fill"
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
        static let textAlignCenter = "text.aligncenter"
        static let textAlignRight = "text.alignright"
        static let increase = "increase.indent"
        static let decrease = "decrease.indent"
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
    
    // MARK: - Weather & Nature
    enum Weather {
        static let sun = "sun.max"
        static let sunFill = "sun.max.fill"
        static let moon = "moon"
        static let moonFill = "moon.fill"
        static let cloud = "cloud"
        static let cloudFill = "cloud.fill"
        static let snowflake = "snowflake"
    }
    
    // MARK: - Charts & Data Visualization
    enum Chart {
        static let chartBar = "chart.bar"
        static let chartBarFill = "chart.bar.fill"
        static let chartPie = "chart.pie"
        static let chartPieFill = "chart.pie.fill"
        static let chartLine = "chart.line.uptrend.xyaxis"
        static let waveform = "waveform"
    }
}
