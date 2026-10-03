import Foundation
import Testing
@testable import CosmicDaybook

// The CSV parser reads UTF-8 bytes instead of `Array(content)` — 16 bytes a
// character — and hands the text back to the character reader whenever a
// delimiter is glued into a larger character (2026-09-26). Pinned here: the
// same headers and rows, byte for byte, as the old parser (`LegacyCSVParser`,
// kept verbatim) for quotes, escaped quotes, embedded newlines, CRLF and lone
// CR, a BOM, multibyte and decomposed text, glued delimiters, ragged and
// header-less input, a large file, and thousands of generated strings; and
// which inputs take the byte path.
@Suite("CSV byte scanner")
struct CSVByteScannerTests {

    /// Every header and field as UTF-8 bytes: equal `String`s can still differ
    /// in their scalars, and the parser must not change a single one.
    private static func bytes(_ table: CSVData?) -> [[[UInt8]]]? {
        guard let table else { return nil }
        return [table.headers.map { Array($0.utf8) }] + table.rows.map { $0.map { Array($0.utf8) } }
    }

    private static func expectSame(_ input: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let old = LegacyCSVParser.parse(string: input)
        let new = CSVParser.parse(string: input)
        #expect(bytes(new) == bytes(old), "\(input.debugDescription)", sourceLocation: sourceLocation)
        #expect(new?.headers == old?.headers, sourceLocation: sourceLocation)
        #expect(new?.rows == old?.rows, sourceLocation: sourceLocation)
    }

    private static func takesBytePath(_ input: String) -> Bool {
        CSVRecordScanner.records(in: CSVParser.normalized(input)) != nil
    }

    // MARK: - Same tables

    nonisolated static let everydayInputs: [String] = [
        "", "\u{FEFF}", "\n\n\n",
        "\u{FEFF}name,age\nAda,9\n",
        "\u{FEFF}\u{FEFF}a,b\n1,2",
        "a,b\r\n1,2\r\n3,4\r\n",
        "a,b\r1,2\r3,4",
        "a,b\r\r\n1,2",
        "a,b\n1,2\r\n3,4\r5,6",
        "a\n\"x\r\ny\"\n",
        "a,b\n1,\"hi\nthere\"\n2,\"x,y\"\n",
        "a\n\"she said \"\"hi\"\"\"\n",
        "a,b\nx\"y,z\n",
        "a,b\n\"never closed,1\n2,3",
        "a,b\n\"\",\"\"\n",
        "label\nAda\n\"\"",
        "a,b\n1,\n2,\n",
        "a,b\n1,2",
        "a,b\n\n1,2\n\n",
        "a,a\n1,2\n",
        "a,,c\n1,2,3\n",
        "a,b,c\n1\n1,2,3,4\n",
        " name , age \nAda,9\n",
        "名前,年齢\n太郎,10\n花子,9\n",
        "👩‍👩‍👧,🇺🇸\n👍🏽,ok\n",
        "José,Zoë\nChloé,Anaïs\n",
        "Jose\u{301},Zoe\u{308}\nChloe\u{301},Anai\u{308}s\n",
        "\"Zoë, the elder\",\"Ana\u{301}\"\n1,2\n",
        "a,\u{1161}b\n",
        "x,🇺🇸,y\n",
        "a\u{0085}b,c\n"
    ]

    /// A delimiter joined into a larger character: the old parser read it as text.
    nonisolated static let gluedInputs: [String] = [
        "a,\u{301}b\n1,2\n",
        "a\n\"x\"\u{301},y\n",
        "a\u{0600},b\n1,2\n",
        "a,\u{200D}x\n1,2\n",
        "a\n\"\u{093E}x\"\n",
        "a,\u{FE0F}b\n",
        "a\n\"x\"\"\u{301}y\"\n",
        "a,\u{0E33}b\n"
    ]

    @Test("Everyday and awkward CSVs read the same, through the byte path", arguments: everydayInputs)
    func everydayInputsMatch(_ input: String) {
        Self.expectSame(input)
        #expect(Self.takesBytePath(input))
    }

    @Test("Glued delimiters read the same, through the character path", arguments: gluedInputs)
    func gluedInputsMatch(_ input: String) {
        Self.expectSame(input)
        #expect(!Self.takesBytePath(input))
    }

    @Test("Data that is not UTF-8 reads the same (Latin-1)")
    func latin1DataMatches() {
        let data = Data([0x6E, 0x61, 0x6D, 0x65, 0x0A, 0x4A, 0x6F, 0x73, 0xE9, 0x0A, 0x22, 0xE0, 0x2C, 0x22, 0x0A])
        #expect(Self.bytes(CSVParser.parse(data: data)) == Self.bytes(LegacyCSVParser.parse(data: data)))
        #expect(CSVParser.parse(data: data)?.rows == [["José"], ["à,"]])
    }

    @Test("A large roster reads the same")
    func largeRosterMatches() {
        var csv = "First Name,Last Name,Birthday,Level,Notes\r\n"
        let names = ["Ada", "José", "Zoë", "Chloe\u{301}", "花子", "O'Brien", "Anaïs"]
        for index in 0..<5_000 {
            let name = names[index % names.count]
            let notes = index.isMultiple(of: 3) ? "\"Loves \"\"bead\"\" work,\nand maps\"" : "plain \(index)"
            csv += "\(name),Family \(index),2016-0\(index % 9 + 1)-1\(index % 9),Lower,\(notes)\r\n"
        }
        Self.expectSame(csv)
        #expect(Self.takesBytePath(csv))
    }

    /// On request, alone (see `BackupExportPeakMemoryTests`): peak heap while
    /// the old and the new parser read a 20,000-row roster exported with CRLF.
    @Test(
        "Peak heap reading a large roster (on request)",
        .enabled(if: ProcessInfo.processInfo.environment["BACKUP_PEAK_MEMORY"] != nil)
    )
    func measurePeakHeap() {
        var csv = "First Name,Last Name,Birthday,Level,Notes\r\n"
        for index in 0..<20_000 {
            csv += "Student \(index),Family \(index),2016-04-1\(index % 9),Lower,\"Likes maps, beads\"\r\n"
        }
        func rise(_ parse: (String) -> CSVData?) -> Int {
            let baseline = BackupExportPeakMemoryTests.PeakSampler.bytesInUse()
            let sampler = BackupExportPeakMemoryTests.PeakSampler()
            sampler.start()
            let table = parse(csv)
            let peak = sampler.stop().values.max() ?? 0
            #expect(table?.rows.count == 20_000)
            return max(0, peak - baseline)
        }
        var old: [Int] = []
        var new: [Int] = []
        for _ in 0..<5 {
            old.append(rise(LegacyCSVParser.parse(string:)))
            new.append(rise(CSVParser.parse(string:)))
        }
        let megabytes = { (bytes: Int) in String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        print("CSVPeakMemory: \(csv.utf8.count) bytes; old \(old.map(megabytes)); new \(new.map(megabytes))")
        #expect((new.sorted()[2]) < (old.sorted()[2]))
    }

    // MARK: - Generated

    /// SplitMix64, so every run tries the same strings.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    @Test("Thousands of generated strings read the same")
    func generatedStringsMatch() {
        let pieces = [
            "a", "b", "Z", " ", ",", ",", "\"", "\"", "\n", "\r", "\r\n", "é", "e\u{301}", "\u{301}", "\u{308}",
            "\u{200D}", "👍", "\u{1F3FD}", "🇺", "\u{0600}", "\u{093E}", "\u{0E33}", "名", "\u{FEFF}", "\u{FE0F}",
            "\u{0085}", "\u{1161}"
        ]
        var generator = SeededGenerator(state: 20_260_926)
        var bytePath = 0
        for _ in 0..<4_000 {
            let length = Int.random(in: 0...24, using: &generator)
            let input = (0..<length).map { _ in pieces.randomElement(using: &generator) ?? "" }.joined()
            Self.expectSame(input)
            if Self.takesBytePath(input) { bytePath += 1 }
        }
        // Both paths are exercised.
        #expect(bytePath > 500)
        #expect(bytePath < 4_000)
    }
}
