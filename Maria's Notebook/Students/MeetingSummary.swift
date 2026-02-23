#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable(description: "A concise summary of a student meeting")
struct MeetingSummary {
    @Guide(description: "A 2-3 sentence summary of the meeting's key outcomes and next steps")
    var overview: String
    
    @Guide(description: "The primary sentiment of the student (e.g., confident, struggling, neutral)")
    var sentiment: String
}
#endif

