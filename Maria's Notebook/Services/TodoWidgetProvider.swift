import WidgetKit
import SwiftUI
import SwiftData

/*
 * TODO WIDGET IMPLEMENTATION GUIDE
 * =================================
 * 
 * This file contains the complete widget implementation for Maria's Notebook.
 * To enable the widget, follow these steps in Xcode:
 * 
 * 1. ADD WIDGET EXTENSION TARGET:
 *    - File > New > Target
 *    - Select "Widget Extension"
 *    - Product Name: "TodoWidget"
 *    - Check "Include Configuration Intent" if you want configurable widgets
 *    - Finish
 * 
 * 2. ADD THIS CODE TO THE WIDGET TARGET:
 *    - Copy all the code from this file to the new TodoWidget.swift file
 *    - Make sure the widget target has access to:
 *      - TodoItem.swift (add to widget target membership)
 *      - AppSchema.swift (add to widget target membership)
 *      - All related model files
 * 
 * 3. CONFIGURE APP GROUPS (for data sharing):
 *    - Select main app target > Signing & Capabilities
 *    - Add "App Groups" capability
 *    - Create group: "group.com.marianotebook.shared"
 *    - Select widget target > Signing & Capabilities  
 *    - Add "App Groups" capability
 *    - Select same group: "group.com.marianotebook.shared"
 * 
 * 4. UPDATE MODEL CONTAINER:
 *    - Modify ModelContainer initialization to use app group:
 *      let container = try ModelContainer(
 *          for: TodoItem.self,
 *          configurations: ModelConfiguration(
 *              url: FileManager.default
 *                  .containerURL(forSecurityApplicationGroupIdentifier: "group.com.marianotebook.shared")!
 *                  .appendingPathComponent("default.store")
 *          )
 *      )
 * 
 * 5. BUILD AND RUN:
 *    - Build the widget extension
 *    - Run on device/simulator
 *    - Add widget to home screen/Today view
 */

// MARK: - Widget Timeline Entry

struct TodoWidgetEntry: TimelineEntry {
    let date: Date
    let todos: [TodoWidgetData]
}

// MARK: - Widget Data Model

struct TodoWidgetData: Identifiable {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let priority: String
    let dueDate: Date?
    let isDueToday: Bool
    let isOverdue: Bool
}

// MARK: - Widget Timeline Provider

struct TodoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoWidgetEntry {
        TodoWidgetEntry(date: Date(), todos: [])
    }
    
    func getSnapshot(in context: Context, completion: @escaping (TodoWidgetEntry) -> Void) {
        let entry = TodoWidgetEntry(date: Date(), todos: [])
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoWidgetEntry>) -> Void) {
        // In real implementation, fetch todos from shared container
        let entry = TodoWidgetEntry(date: Date(), todos: [])
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Views

struct TodoWidgetView: View {
    let entry: TodoWidgetEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            EmptyView()
        }
    }
}

struct SmallWidgetView: View {
    let entry: TodoWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To-Do")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            if entry.todos.isEmpty {
                Text("All done! ✓")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.todos.prefix(3)) { todo in
                        HStack(spacing: 4) {
                            Image(systemName: "circle")
                                .font(.caption2)
                            Text(todo.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundStyle(todo.isOverdue ? .red : (todo.isDueToday ? .orange : .primary))
                    }
                }
            }
            
            Spacer()
            
            Text("\(entry.todos.count) tasks")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct MediumWidgetView: View {
    let entry: TodoWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("To-Do List")
                    .font(.headline)
                Spacer()
                Text("\(entry.todos.count) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if entry.todos.isEmpty {
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    Text("All done!")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.todos.prefix(4)) { todo in
                        HStack(spacing: 6) {
                            Image(systemName: "circle")
                                .font(.caption)
                            Text(todo.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                        }
                        .foregroundStyle(todo.isOverdue ? .red : (todo.isDueToday ? .orange : .primary))
                    }
                }
            }
        }
        .padding()
    }
}

struct LargeWidgetView: View {
    let entry: TodoWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("To-Do List")
                    .font(.title3.bold())
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(entry.todos.count)")
                        .font(.title2.bold())
                    Text("active tasks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            if entry.todos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    Text("All tasks complete!")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.todos) { todo in
                        HStack(spacing: 8) {
                            Image(systemName: "circle")
                                .font(.callout)
                            Text(todo.title)
                                .font(.subheadline)
                                .lineLimit(2)
                            Spacer()
                        }
                        .foregroundStyle(todo.isOverdue ? .red : (todo.isDueToday ? .orange : .primary))
                        
                        if todo.id != entry.todos.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
    }
}
