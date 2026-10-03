import Foundation
import OSLog
import CoreGraphics

#if canImport(ImagePlayground)
import ImagePlayground
#endif

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum StoryCoverGeneratorError: LocalizedError {
    case unavailable
    case noImageReturned
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Making a cover needs Image Playground, which isn't available on this device."
        case .noImageReturned:
            return "Image Playground didn't make a picture. Try again."
        case .generationFailed(let message):
            return message
        }
    }
}

/// Generates an illustrated cover for a story with Apple Image Playground,
/// constrained to abstract / no-people prompts because Image Playground's
/// text-only path requires a source face for any prompt that implies specific
/// characters.
enum StoryCoverGenerator {
    private static let logger = Logger.stories

    /// Whether this build can generate a cover at all.
    static var isAvailable: Bool {
        #if canImport(ImagePlayground)
        true
        #else
        false
        #endif
    }

    // MARK: - Public

    static func generateCover(
        title: String,
        themes: [String]
    ) async throws -> Data {
        try await generateWithImagePlayground(title: title, themes: themes)
    }

    // MARK: - Image Playground path

    private static func generateWithImagePlayground(
        title: String,
        themes: [String]
    ) async throws -> Data {
        #if canImport(ImagePlayground)
        let cleanedThemes = stripPersonThemes(themes)
        let prompt = buildHeuristicPrompt(title: title, themes: cleanedThemes)
        logger.info("Generating story cover (Image Playground): \(prompt, privacy: .public)")

        do {
            return try await runImagePlayground(prompt: prompt, style: .illustration)
        } catch StoryCoverGeneratorError.unavailable {
            throw StoryCoverGeneratorError.unavailable
        } catch StoryCoverGeneratorError.noImageReturned {
            throw StoryCoverGeneratorError.noImageReturned
        } catch let illustrationError as StoryCoverGeneratorError {
            logger.info("Illustration style failed; retrying with .sketch")
            do {
                return try await runImagePlayground(prompt: prompt, style: .sketch)
            } catch {
                throw illustrationError
            }
        }
        #else
        throw StoryCoverGeneratorError.unavailable
        #endif
    }

    #if canImport(ImagePlayground)
    private static func runImagePlayground(
        prompt: String,
        style: ImagePlaygroundStyle
    ) async throws -> Data {
        let creator: ImageCreator
        do {
            creator = try await ImageCreator()
        } catch {
            logger.warning("ImageCreator init failed: \(error.localizedDescription, privacy: .public)")
            throw StoryCoverGeneratorError.unavailable
        }

        let stream = creator.images(
            for: [.text(prompt)],
            style: style,
            limit: 1
        )

        do {
            for try await created in stream {
                if let data = jpegData(from: created.cgImage) {
                    return data
                }
            }
        } catch {
            let styleDesc = String(describing: style)
            let raw = error.localizedDescription
            logger.warning("Generation failed (style=\(styleDesc, privacy: .public)): \(raw, privacy: .public)")
            throw StoryCoverGeneratorError.generationFailed(friendlyMessage(for: error))
        }

        throw StoryCoverGeneratorError.noImageReturned
    }
    #endif

    // MARK: - Prompt construction

    /// Themes whose words map to a known person-noun are stripped — used to satisfy
    /// Image Playground's "no source face" guard.
    static func stripPersonThemes(_ themes: [String]) -> [String] {
        themes.compactMap { theme in
            let lowered = theme.lowercased()
            let words = lowered.split { !$0.isLetter }.map(String.init)
            for word in words where personWords.contains(word) {
                return nil
            }
            return theme.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    }

    static func buildHeuristicPrompt(title: String, themes: [String]) -> String {
        let cleaned = stripPersonThemes(themes)
        var components: [String] = [
            "Storybook cover illustration, painterly, soft watercolor, no people"
        ]
        if !cleaned.isEmpty {
            let themeList = cleaned.prefix(5).joined(separator: ", ")
            components.append("Area: \(themeList)")
        }
        if let hint = settingHint(themes: cleaned, title: title) {
            components.append("Scene: \(hint)")
        }
        return components.joined(separator: ". ")
    }

    static func settingHint(themes: [String], title: String) -> String? {
        let sources = themes + [title]
        for source in sources {
            let lowered = source.lowercased()
            if let hint = settingHints[lowered] { return hint }
            let words = lowered.split { !$0.isLetter }.map(String.init)
            for word in words {
                if let hint = settingHints[word] { return hint }
            }
        }
        return nil
    }

    private static func friendlyMessage(for error: Error) -> String {
        let raw = error.localizedDescription
        if raw.localizedCaseInsensitiveContains("source image")
            || raw.localizedCaseInsensitiveContains("face") {
            return "Image Playground can't draw people. "
                + "Remove themes like \"family\" or \"hero,\" then try again."
        }
        return "Couldn't make a cover. Try again."
    }

    // MARK: - Encoding

    private static func jpegData(from cgImage: CGImage) -> Data? {
        #if os(macOS)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        #else
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.85)
        #endif
    }

    // MARK: - Vocabulary

    private static let personWords: Set<String> = [
        "family", "families", "mother", "mom", "mommy", "father", "dad", "daddy",
        "parent", "parents", "brother", "sister", "son", "daughter",
        "grandmother", "grandfather", "grandma", "grandpa", "grandparent", "grandparents",
        "husband", "wife", "uncle", "aunt", "cousin", "twin", "twins", "orphan",
        "boy", "boys", "girl", "girls", "child", "children", "kid", "kids",
        "baby", "babies", "infant", "toddler", "teen", "teenager",
        "person", "people", "woman", "women", "man", "men", "lady", "gentleman",
        "boyfriend", "girlfriend",
        "teacher", "student", "principal", "professor", "pupil",
        "hero", "heroine", "villain", "monster",
        "princess", "prince", "king", "queen", "knight", "ruler",
        "witch", "wizard", "captain", "sailor", "soldier", "farmer",
        "doctor", "nurse", "lord", "lady", "master", "servant", "slave",
        "neighbor", "neighbour", "stranger", "traveler", "traveller"
    ]

    private static let settingHints: [String: String] = [
        "lighthouse": "ocean cove, lighthouse on cliffs, gentle waves, warm sunset",
        "ocean": "ocean waves, blue sky, distant horizon",
        "sea": "calm sea, soft horizon, gentle clouds",
        "cove": "rocky cove, gentle waves, seabirds",
        "harbor": "stone harbor, fishing boats, lanterns",
        "harbour": "stone harbour, fishing boats, lanterns",
        "island": "small green island, surrounding sea, soft clouds",
        "river": "winding river, willow trees, gentle bend",
        "lake": "still lake at dawn, mist, pine trees",
        "boat": "small wooden boat, calm water, golden hour",
        "ship": "tall ship, rolling waves, dramatic sky",
        "forest": "ancient forest, dappled light, mossy trees",
        "woods": "deep woods, golden light, ferns",
        "tree": "great old tree, soft meadow, gentle light",
        "trees": "grove of tall trees, dappled light",
        "mountain": "snow-capped mountains, alpine meadow",
        "mountains": "snow-capped mountains, alpine meadow",
        "valley": "rolling green valley, soft mist, sunrise",
        "meadow": "wildflower meadow, gentle breeze, butterflies",
        "field": "open field, golden grass, soft sky",
        "fields": "patchwork fields, hedgerows, distant hills",
        "desert": "sand dunes, warm sunset, distant cacti",
        "garden": "lush garden, blooming flowers, butterflies",
        "castle": "stone castle on a hill, dramatic sky",
        "tower": "tall stone tower, windswept hill",
        "village": "stone cottages, cobblestone streets, warm lanterns",
        "town": "small town rooftops, warm windows, evening glow",
        "city": "old city skyline, soft windows, evening light",
        "school": "old schoolhouse, warm wood, autumn leaves",
        "library": "tall bookshelves, warm reading lamp",
        "farm": "rolling fields, red barn, golden wheat",
        "barn": "wooden barn, hay bales, warm sunset",
        "cottage": "thatched cottage, climbing roses, soft path",
        "night": "starry night sky, full moon, deep blue",
        "stars": "starry sky, dreamy nebula",
        "moon": "crescent moon, soft clouds, deep blue sky",
        "sun": "warm sunset, golden hour",
        "rainbow": "soft rainbow, pastel sky, gentle rain",
        "storm": "rolling clouds, dramatic sky, distant lightning",
        "winter": "snowy landscape, falling snow, evergreen trees",
        "snow": "snowy landscape, falling snow, evergreen trees",
        "spring": "blooming flowers, soft green meadow, fresh light",
        "autumn": "autumn leaves, golden trees, warm hues",
        "fall": "autumn leaves, golden trees, warm hues",
        "summer": "sunny meadow, blue sky, wildflowers",
        "rain": "gentle rain, glistening leaves, soft puddles",
        "magic": "magical sparkles, glowing motes, soft mist",
        "dream": "dreamy clouds, pastel sky, drifting feathers",
        "adventure": "winding path, distant horizon, mountains beyond",
        "journey": "winding road, distant mountains, golden light",
        "travel": "winding road, distant mountains",
        "courage": "soaring eagle, mountain summit, golden sky",
        "nature": "lush meadow, gentle stream, sunlight through leaves",
        "kindness": "warm light, soft pastels, gentle landscape",
        "friendship": "warm light, soft pastels, gentle landscape",
        "animals": "woodland creatures, cozy clearing, soft light",
        "dragon": "majestic dragon silhouette, distant mountain, sunset",
        "owl": "wise owl in moonlit tree",
        "fox": "red fox in autumn woods",
        "rabbit": "rabbit in spring meadow"
    ]
}
