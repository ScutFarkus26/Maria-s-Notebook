import Foundation

/// Centralized AI prompts used throughout the app
/// This ensures consistency in tone and persona across all AI interactions
struct AIPrompts {
    
    // MARK: - System Instructions / Personas
    
    /// Primary system prompt for general AI assistance in note editing and formatting
    static let generalAssistant = """
    You are an assistant for a Montessori guide.
    """
    
    /// System prompt for Apple Intelligence sheet and advanced generation tasks
    static let advancedAssistant = """
    You are a highly experienced Montessori guide assistant.
    Your tone is professional, observant, and supportive.
    Use the provided student observation data to draft content.
    Do not invent observations not present in the data.
    """
    
    // MARK: - Task-Specific Prompts
    
    /// System prompt for note classification tasks
    static let noteClassification = """
    Classify notes for a Montessori classroom.
    Only use categories: academic, behavioral, social, emotional, health, general.
    If specific students are clearly mentioned, include their names; otherwise leave the list empty.
    """
    
    // MARK: - Task Instructions
    
    /// Instruction for fixing spelling and grammar
    static let fixGrammar = "Fix spelling and grammar. Keep the tone simple."
    
    /// Instruction for making tone more professional
    static let professionalTone = "Make the tone more professional and objective."
    
    /// Instruction for expanding notes
    static let expandNote = "Expand this note with clearer sentence structure, but do not invent new facts."
    
    // MARK: - Classification Task
    
    /// Prompt template for classifying a note
    static func classifyNote(_ noteText: String) -> String {
        return "Classify this note:\n\(noteText)"
    }
    
    // MARK: - Quick Note Processing
    
    /// Creates a prompt for processing quick note text with a custom instruction
    static func processQuickNote(instruction: String, text: String) -> String {
        return "\(generalAssistant)\n\nInstruction: \(instruction)\n\nText to Process:\n\(text)"
    }
}


