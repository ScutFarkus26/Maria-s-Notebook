import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

/// Service for importing attachments with smart lesson detection
struct LessonAttachmentImporter {
    private static let logger = Logger.lessons

    let viewContext: NSManagedObjectContext
    
    /// Suggests lessons that might be related to the given file based on filename analysis
    /// - Parameter fileURL: The URL of the file to import
    /// - Returns: Array of suggested lessons, sorted by relevance
    func suggestLessons(for fileURL: URL) -> [CDLesson] {
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        let searchTerms = extractSearchTerms(from: fileName)
        
        let descriptor: NSFetchRequest<CDLesson> = NSFetchRequest(entityName: "Lesson")
        descriptor.sortDescriptors = [NSSortDescriptor(key: "sortIndex", ascending: true)]
        
        let allLessons: [CDLesson]
        do {
            allLessons = try viewContext.fetch(descriptor)
        } catch {
            Self.logger.warning("Failed to fetch lessons: \(error)")
            return []
        }
        
        // Score each lesson based on how well it matches the search terms
        let scoredLessons = allLessons.map { lesson in
            (lesson: lesson, score: calculateRelevanceScore(lesson: lesson, searchTerms: searchTerms))
        }
        
        // Filter to only lessons with positive scores and sort by score
        return scoredLessons
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .map(\.lesson)
    }
    
    /// Extracts meaningful search terms from a filename
    private func extractSearchTerms(from fileName: String) -> [String] {
        // Remove common file naming conventions
        let cleaned = fileName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        
        // Split into words and filter out very short words
        let words = cleaned
            .components(separatedBy: " ")
            .map { $0.trimmed().lowercased() }
            .filter { $0.count > 2 }
        
        return words
    }
    
    /// Calculates how relevant a lesson is to the search terms
    private func calculateRelevanceScore(lesson: CDLesson, searchTerms: [String]) -> Int {
        var score = 0
        
        let lessonName = lesson.name.lowercased()
        let subject = lesson.subject.lowercased()
        let group = lesson.group.lowercased()
        let subheading = lesson.subheading.lowercased()
        
        for term in searchTerms {
            // Exact word matches in name get highest score
            let hasWordMatch = lessonName.contains(" \(term) ")
                || lessonName.hasPrefix("\(term) ")
                || lessonName.hasSuffix(" \(term)")
            if hasWordMatch {
                score += 10
            } else if lessonName.contains(term) {
                score += 5
            }
            
            // Subject matches
            if subject == term {
                score += 8
            } else if subject.contains(term) {
                score += 4
            }
            
            // Group matches
            if group == term {
                score += 6
            } else if group.contains(term) {
                score += 3
            }
            
            // Subheading matches
            if subheading.contains(term) {
                score += 2
            }
        }
        
        return score
    }
    
    /// Gets recently viewed or modified lessons (placeholder for actual implementation)
    func getRecentLessons(limit: Int = 5) -> [CDLesson] {
        let descriptor: NSFetchRequest<CDLesson> = NSFetchRequest(entityName: "Lesson")
        descriptor.sortDescriptors = [NSSortDescriptor(key: "sortIndex", ascending: false)]
        
        let lessons: [CDLesson]
        do {
            lessons = try viewContext.fetch(descriptor)
        } catch {
            Self.logger.warning("Failed to fetch lessons: \(error)")
            return []
        }
        
        return Array(lessons.prefix(limit))
    }
}

/// Sheet view for selecting a lesson when importing an attachment
struct LessonAttachmentImportSheet: View {
    private static let logger = Logger.lessons

    let fileURL: URL
    let onImport: (CDLesson, AttachmentScope) -> Void
    let onCancel: () -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedLesson: CDLesson?
    @State private var selectedScope: AttachmentScope = .lesson
    @State private var searchText = ""
    @State private var suggestedLessons: [CDLesson] = []
    @State private var allLessons: [CDLesson] = []
    
    private var importer: LessonAttachmentImporter {
        LessonAttachmentImporter(viewContext: viewContext)
    }
    
    private var filteredLessons: [CDLesson] {
        if searchText.isEmpty {
            return allLessons
        }
        
        let lowercased = searchText.lowercased()
        return allLessons.filter { lesson in
            lesson.name.lowercased().contains(lowercased) ||
            lesson.subject.lowercased().contains(lowercased) ||
            lesson.group.lowercased().contains(lowercased)
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                
                Text("Import Attachment")
                    .font(AppTheme.ScaledFont.header)
                
                Text(fileURL.lastPathComponent)
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.top, 20)
            
            Divider()
            
            // Suggested lessons
            if !suggestedLessons.isEmpty && searchText.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Suggested Lessons")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    ForEach(suggestedLessons.prefix(3)) { lesson in
                        LessonSelectionRow(
                            lesson: lesson,
                            isSelected: selectedLesson?.id == lesson.id,
                            onSelect: { selectedLesson = lesson }
                        )
                    }
                }
                .padding(.horizontal)
                
                Divider()
            }
            
            // Search and lesson list
            VStack(alignment: .leading, spacing: 12) {
                Text("All Lessons")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal)
                
                TextField("Search lessons...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredLessons) { lesson in
                            LessonSelectionRow(
                                lesson: lesson,
                                isSelected: selectedLesson?.id == lesson.id,
                                onSelect: { selectedLesson = lesson }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 300)
            }
            
            // Scope selector
            if selectedLesson != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Attachment Scope")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    Picker("Scope", selection: $selectedScope) {
                        ForEach(AttachmentScope.allCases) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Text(selectedScope.description)
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Import") {
                    if let lesson = selectedLesson {
                        onImport(lesson, selectedScope)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedLesson == nil)
            }
            .padding(.bottom, 20)
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadLessons()
        }
    }
    
    private func loadLessons() {
        // Get suggested lessons
        suggestedLessons = importer.suggestLessons(for: fileURL)
        
        // Pre-select the top suggestion
        if let topSuggestion = suggestedLessons.first {
            selectedLesson = topSuggestion
        }
        
        // Load all lessons
        let descriptor: NSFetchRequest<CDLesson> = NSFetchRequest(entityName: "Lesson")
        descriptor.sortDescriptors = [
                NSSortDescriptor(key: "subject", ascending: true),
                NSSortDescriptor(key: "group", ascending: true),
                NSSortDescriptor(key: "orderInGroup", ascending: true)
            ]
        
        do {
            allLessons = try viewContext.fetch(descriptor)
        } catch {
            Self.logger.warning("Failed to fetch lessons: \(error)")
        }
    }
}

/// Row view for lesson selection
struct LessonSelectionRow: View {
    let lesson: CDLesson
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.system(size: 16))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.name)
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack(spacing: 6) {
                        if !lesson.subject.isEmpty {
                            Text(lesson.subject)
                                .font(AppTheme.ScaledFont.captionSmall)
                                .foregroundStyle(.secondary)
                        }
                        if !lesson.subject.isEmpty && !lesson.group.isEmpty {
                            Text("•")
                                .foregroundStyle(.secondary)
                        }
                        if !lesson.group.isEmpty {
                            Text(lesson.group)
                                .font(AppTheme.ScaledFont.captionSmall)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(UIConstants.OpacityConstants.light) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Import Sheet") {
    LessonAttachmentImportSheet(
        fileURL: URL(fileURLWithPath: "/tmp/Math-Decimal-System-Practice.pdf"),
        onImport: { _, _ in },
        onCancel: {}
    )
    .previewEnvironment()
}
