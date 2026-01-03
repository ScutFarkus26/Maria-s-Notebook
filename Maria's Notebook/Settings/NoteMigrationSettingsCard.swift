import SwiftUI
import SwiftData

struct NoteMigrationSettingsCard: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingMigrationSheet = false
    @State private var legacyNoteCount: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Migrate legacy notes to the unified Note system")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary)
            
            HStack {
                if legacyNoteCount > 0 {
                    Text("\(legacyNoteCount) legacy notes found")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No legacy notes found")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    showingMigrationSheet = true
                } label: {
                    Text("Open Migration")
                }
                .buttonStyle(.bordered)
                .disabled(legacyNoteCount == 0)
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showingMigrationSheet) {
            #if os(macOS)
            NoteMigrationView()
                .frame(minWidth: 500, minHeight: 400)
                .presentationSizingFitted()
            #else
            NavigationStack {
                NoteMigrationView()
                    .navigationTitle("Note Migration")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showingMigrationSheet = false
                            }
                        }
                    }
            }
            #endif
        }
        .onAppear {
            countLegacyNotes()
        }
    }
    
    private func countLegacyNotes() {
        Task { @MainActor in
            do {
                let scopedCount = try modelContext.fetch(FetchDescriptor<ScopedNote>()).count
                let workCount = try modelContext.fetch(FetchDescriptor<WorkNote>()).count
                let meetingCount = try modelContext.fetch(FetchDescriptor<MeetingNote>()).count
                legacyNoteCount = scopedCount + workCount + meetingCount
            } catch {
                legacyNoteCount = 0
            }
        }
    }
}


