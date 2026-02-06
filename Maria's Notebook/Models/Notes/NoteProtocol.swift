import Foundation
import SwiftData

/// Base protocol for all domain-specific note types.
///
/// This protocol replaces the polymorphic Note model with type-safe, domain-specific implementations.
/// Each concrete type has a single required relationship instead of 16 optional ones.
///
/// **Architecture Decision:** Phase 3 Data Model Consolidation
/// - See PHASE_3_PLAN.md for migration strategy
/// - See ARCHITECTURE_DECISIONS.md for rationale
protocol NoteProtocol {
    /// Unique identifier
    var id: UUID { get set }
    
    /// Note content (text, markdown, or rich content)
    var content: String { get set }
    
    /// When the note was created
    var createdAt: Date { get set }
    
    /// Optional author/creator ID
    var authorID: UUID? { get set }
    
    /// Note category (academic, behavioral, social, etc.)
    var category: NoteCategory { get set }
    
    /// When the note was last modified (optional)
    var modifiedAt: Date? { get set }
}

// Note: NoteCategory and NoteScope enums are defined in Note.swift
// They are reused by all domain-specific note types
