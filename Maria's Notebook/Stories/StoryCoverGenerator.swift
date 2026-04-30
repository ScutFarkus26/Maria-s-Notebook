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
            return "No cover-generation provider is available. Add an OpenAI API key in "
                + "Settings, or enable Apple Intelligence."
        case .noImageReturned:
            return "The image provider didn't return an image."
        case .generationFailed(let message):
            return message
        }
    }
}

/// Generates an illustrated cover for a story.
///
/// Pipeline (in order of preference):
/// 1. **OpenAI `gpt-image-1`** — used when an OpenAI API key is configured. Highest quality.
///    The prompt is refined by Claude when an Anthropic key is also configured.
/// 2. **Apple Image Playground** — used as a fallback when no OpenAI key exists.
///    Constrained to abstract / no-people prompts because Image Playground's text-only
///    path requires a source face for any prompt that implies specific characters.
enum StoryCoverGenerator {
    private static let logger = Logger.stories

    enum Provider: String {
        case openAI
        case imagePlayground
        case none
    }

    /// Whether ANY provider is currently configured to generate a cover.
    static var isAvailable: Bool {
        provider != .none
    }

    /// The provider that will actually be used given current keys / system state.
    static var provider: Provider {
        if OpenAIAPIClient.hasAPIKey() {
            return .openAI
        }
        #if canImport(ImagePlayground)
        return .imagePlayground
        #else
        return .none
        #endif
    }

    // MARK: - Public

    static func generateCover(
        title: String,
        themes: [String],
        summary: String
    ) async throws -> Data {
        switch provider {
        case .openAI:
            return try await generateWithOpenAI(title: title, themes: themes, summary: summary)
        case .imagePlayground:
            return try await generateWithImagePlayground(title: title, themes: themes)
        case .none:
            throw StoryCoverGeneratorError.unavailable
        }
    }

    // MARK: - OpenAI path

    private static func generateWithOpenAI(
        title: String,
        themes: [String],
        summary: String
    ) async throws -> Data {
        // Build the visual prompt. Claude refines it when available; otherwise we use
        // the same theme/title/setting-hint heuristic as the Image Playground path.
        let prompt: String
        if AnthropicAPIClient.hasAPIKey() {
            do {
                prompt = try await buildPromptWithClaude(
                    title: title, themes: themes, summary: summary
                )
                logger.info("Using Claude-refined cover prompt: \(prompt, privacy: .public)")
            } catch {
                logger.warning("Claude prompt refinement failed; using heuristic. \(error.localizedDescription, privacy: .public)")
                prompt = buildHeuristicPrompt(title: title, themes: themes)
            }
        } else {
            prompt = buildHeuristicPrompt(title: title, themes: themes)
        }

        let client = OpenAIAPIClient()
        do {
            return try await client.generateImage(prompt: prompt, size: .portrait, quality: .low)
        } catch let error as OpenAIAPIError {
            throw StoryCoverGeneratorError.generationFailed(error.errorDescription ?? "OpenAI failed")
        } catch {
            throw StoryCoverGeneratorError.generationFailed(error.localizedDescription)
        }
    }

    /// Asks Claude (via the existing Anthropic client) to write a single-paragraph,
    /// vivid prompt suitable for `gpt-image-1`. Title and summary are allowed —
    /// gpt-image-1 has fewer person restrictions than Image Playground.
    private static func buildPromptWithClaude(
        title: String,
        themes: [String],
        summary: String
    ) async throws -> String {
        let themeList = themes.prefix(7).joined(separator: ", ")
        let userMessage = """
        Title: \(title)
        Themes: \(themeList)
        Summary: \(summary.trimmingCharacters(in: .whitespacesAndNewlines))
        """

        let system = """
        You are an art director writing a single image-generation prompt for a children's \
        book cover. Output ONE concise paragraph (60-100 words) describing a vivid, \
        evocative cover illustration. Focus on setting, mood, palette, composition, \
        and lighting. Style: warm, painterly, watercolor or gouache, suitable for ages 4-10. \
        Do NOT include the title text in the image; do NOT use quotation marks; do NOT \
        preface with "Here is" or similar. Output the prompt only.
        """

        let client = AnthropicAPIClient()
        let response = try await client.generateText(
            prompt: userMessage,
            systemMessage: system,
            temperature: 0.6,
            maxTokens: 400,
            model: "claude-haiku-4-5",
            timeout: 30
        )
        let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw StoryCoverGeneratorError.generationFailed("Empty Claude response") }
        return cleaned
    }

    // MARK: - Image Playground path (fallback)

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
            let message = friendlyMessage(for: error)
            logger.warning("Generation failed (style=\(String(describing: style), privacy: .public)): \(message, privacy: .public)")
            throw StoryCoverGeneratorError.generationFailed(message)
        }

        throw StoryCoverGeneratorError.noImageReturned
    }
    #endif

    // MARK: - Prompt construction (heuristic, used for Image Playground & OpenAI fallback)

    /// Themes whose words map to a known person-noun are stripped — used to satisfy
    /// Image Playground's "no source face" guard. The OpenAI path also uses this to
    /// keep prompts focused on scene/mood when Claude isn't available.
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
            components.append("Subject: \(themeList)")
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
            return "Image Playground interpreted these themes as implying people. "
                + "Try removing person-like themes (e.g. \"family\", \"hero\") and regenerate."
        }
        return raw
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
