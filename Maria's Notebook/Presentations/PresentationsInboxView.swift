// PresentationsInboxView.swift
// Inbox section extracted from PresentationsView

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PresentationsInboxView: View {
    let readyLessons: [StudentLesson]
    let blockedLessons: [StudentLesson]
    let getBlockingContracts: (StudentLesson) -> [UUID: WorkContract]
    let filteredSnapshot: (StudentLesson) -> StudentLessonSnapshot
    let missWindow: PresentationsMissWindow
    @Binding var missWindowRaw: String
    @Binding var selectedStudentLessonForDetail: StudentLesson?
    @Binding var isInboxTargeted: Bool
    @Binding var isCalendarMinimized: Bool
    
    @Environment(\.modelContext) private var modelContext
    
    @Query private var studentLessons: [StudentLesson]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "tray")
                    .imageScale(.large)
                    .foregroundStyle(Color.accentColor)
                Text("Presentations")
                    .font(.headline)
                Spacer()
                
                #if os(iOS)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isCalendarMinimized.toggle()
                    }
                } label: {
                    Image(systemName: isCalendarMinimized ? "calendar" : "calendar.badge.minus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.primary.opacity(0.1))
                        .clipShape(Circle())
                }
                #endif
                
                Picker("Missed", selection: Binding(
                    get: { missWindow },
                    set: { missWindowRaw = $0.rawValue }
                )) {
                    ForEach(PresentationsMissWindow.allCases, id: \.self) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Text("\(readyLessons.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // 1. BLOCKED / WAITING SECTION
                    if !blockedLessons.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("On Deck (Waiting for Work)", systemImage: "hourglass")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(blockedLessons, id: \.id) { sl in
                                        inboxRow(sl, blockingContracts: getBlockingContracts(sl))
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                        }
                        .padding(.top, 12)
                    }

                    // 2. READY SECTION
                    if readyLessons.isEmpty {
                        if blockedLessons.isEmpty {
                            ContentUnavailableView("All Caught Up", systemImage: "checkmark.circle", description: Text("No unscheduled presentations."))
                                .padding(.top, 40)
                        } else {
                            Text("All planned presentations are waiting on work.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 20)
                        }
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], alignment: .leading, spacing: 8) {
                            ForEach(readyLessons, id: \.id) { sl in
                                inboxRow(sl)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .overlay {
            if isInboxTargeted {
                Color.accentColor.opacity(0.15)
                    .allowsHitTesting(false)
                
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(2)
                    .allowsHitTesting(false)
                
                VStack {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(Color.accentColor)
                    Text("Drop to Unschedule")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
                .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.text], delegate: InboxDropDelegate(
            modelContext: modelContext,
            studentLessons: studentLessons,
            isTargeted: $isInboxTargeted
        ))
    }

    @ViewBuilder
    private func inboxRow(_ sl: StudentLesson, blockingContracts: [UUID: WorkContract] = [:]) -> some View {
        HStack(spacing: 0) {
            StudentLessonPill(
                snapshot: filteredSnapshot(sl),
                day: Date(),
                targetStudentLessonID: sl.id,
                enableMissHighlight: true,
                blockingContracts: blockingContracts
            )
            .onTapGesture { selectedStudentLessonForDetail = sl }
            .onDrag {
                let provider = NSItemProvider(object: NSString(string: sl.id.uuidString))
                provider.suggestedName = sl.lesson?.name ?? "Lesson"
                return provider
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - Drop Delegate for Inbox
private struct InboxDropDelegate: DropDelegate {
    let modelContext: ModelContext
    let studentLessons: [StudentLesson]
    @Binding var isTargeted: Bool
    
    func dropEntered(info: DropInfo) {
        withAnimation { isTargeted = true }
    }
    
    func dropExited(info: DropInfo) {
        withAnimation { isTargeted = false }
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }
    
    func performDrop(info: DropInfo) -> Bool {
        withAnimation { isTargeted = false }
        let providers = info.itemProviders(for: [.text])
        guard let provider = providers.first else { return false }
        
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let str = reading as? String, let id = UUID(uuidString: str) else { return }
            
            Task { @MainActor in
                if let sl = studentLessons.first(where: { $0.id == id }) {
                    // Only process if it actually has a schedule to clear
                    if sl.scheduledFor != nil {
                        sl.scheduledFor = nil
                        try? modelContext.save()
                    }
                }
            }
        }
        return true
    }
}

