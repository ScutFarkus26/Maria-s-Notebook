import SwiftUI
import SwiftData

/// Main chat-style AI planning assistant view.
/// Presents recommendations inline with conversation messages,
/// supports free-text follow-up questions, and allows accepting/rejecting recommendations.
struct AIPlanningAssistantView: View {
    let mode: PlanningMode
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    
    @State private var vm: LessonPlanningViewModel
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    
    init(mode: PlanningMode) {
        self.mode = mode
        _vm = State(wrappedValue: LessonPlanningViewModel(mode: mode))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            headerBar
            
            Divider()
            
            // Main content
            #if os(macOS)
            macOSLayout
            #else
            iOSLayout
            #endif
            
            Divider()
            
            // Input bar
            inputBar
        }
        #if os(macOS)
        .frame(minWidth: 700, idealWidth: 900, minHeight: 550, idealHeight: 700)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear {
            vm.configure(modelContext: modelContext, mcpClient: dependencies.mcpClient)
            vm.startPlanning()
        }
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.modeTitle)
                    .font(AppTheme.ScaledFont.titleSmall)
                
                Text(vm.currentStep.displayLabel)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Depth picker
            Picker("Depth", selection: $vm.selectedDepth) {
                ForEach(PlanningDepth.allCases) { depth in
                    Text(depth.displayName).tag(depth)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            
            if !vm.estimatedCost.isEmpty {
                Text(vm.estimatedCost)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }
            
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - macOS Layout (sidebar + chat)
    
    #if os(macOS)
    private var macOSLayout: some View {
        HStack(spacing: 0) {
            // Recommendations sidebar
            if !vm.recommendations.isEmpty {
                recommendationsSidebar
                    .frame(width: 280)
                
                Divider()
            }
            
            // Chat area
            chatArea
        }
    }
    #endif
    
    // MARK: - iOS Layout (stacked)
    
    private var iOSLayout: some View {
        chatArea
    }
    
    // MARK: - Chat Area
    
    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(vm.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                    
                    // Show inline recommendations on iOS
                    #if os(iOS)
                    if !vm.recommendations.isEmpty && vm.currentStep == .presentingPlan {
                        recommendationsSection
                    }
                    #endif
                    
                    if vm.isLoading {
                        loadingIndicator
                    }
                    
                    if let error = vm.errorMessage {
                        errorBanner(error)
                    }
                }
                .padding(20)
            }
            .onChange(of: vm.messages.count) { _, _ in
                if let lastID = vm.messages.last?.id {
                    adaptiveWithAnimation {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Recommendations Sidebar (macOS)
    
    #if os(macOS)
    private var recommendationsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recommendations")
                    .font(AppTheme.ScaledFont.titleSmall)
                Spacer()
                Text("\(vm.acceptedRecommendations.count) accepted")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(vm.recommendations) { rec in
                        PlanningRecommendationCard(
                            recommendation: rec,
                            onAccept: { vm.acceptRecommendation(rec.id) },
                            onReject: { vm.rejectRecommendation(rec.id) },
                            onAskWhy: { askWhy(about: rec) }
                        )
                    }
                }
                .padding(12)
            }
            
            if vm.canApplyPlan {
                Divider()
                applyButton
                    .padding(12)
            }
        }
        .background(.background)
    }
    #endif
    
    // MARK: - Inline Recommendations (iOS)
    
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recommendations")
                    .font(.headline)
                Spacer()
                if vm.canApplyPlan {
                    applyButton
                }
            }
            
            ForEach(vm.recommendations) { rec in
                PlanningRecommendationCard(
                    recommendation: rec,
                    onAccept: { vm.acceptRecommendation(rec.id) },
                    onReject: { vm.rejectRecommendation(rec.id) },
                    onAskWhy: { askWhy(about: rec) }
                )
            }
        }
    }
    
    // MARK: - Week Plan
    
    private var weekPlanSection: some View {
        Group {
            if let plan = vm.weekPlan {
                WeekPlanOverviewView(
                    weekPlan: plan,
                    onAcceptRecommendation: { vm.acceptRecommendation($0) },
                    onRejectRecommendation: { vm.rejectRecommendation($0) }
                )
            }
        }
    }
    
    // MARK: - Message Row
    
    @ViewBuilder
    private func messageRow(_ message: PlanningMessage) -> some View {
        switch message.role {
        case .teacher:
            HStack {
                Spacer()
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: 500, alignment: .trailing)
            }
            
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: 500, alignment: .leading)
                
                // Show week plan if this is a whole-class result
                if vm.weekPlan != nil && !message.recommendationIDs.isEmpty {
                    weekPlanSection
                }
            }
            
        case .system:
            Text(message.content)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .italic()
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    // MARK: - Input Bar
    
    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask a question or refine the plan...", text: $inputText)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .onSubmit { sendMessage() }
                .disabled(vm.isLoading || vm.currentStep == .idle)
            
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.accentColor)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLoading)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Apply Button
    
    private var applyButton: some View {
        Button(action: { vm.applyPlan() }, label: {
            Label("Apply \(vm.acceptedRecommendations.count) Lesson\(vm.acceptedRecommendations.count == 1 ? "" : "s")", systemImage: "checkmark.circle")
        })
        .buttonStyle(.borderedProminent)
        .disabled(vm.isLoading)
    }
    
    // MARK: - Loading & Error
    
    private var loadingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(vm.currentStep.displayLabel)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }
    
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.warning)
            Text(message)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(AppColors.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        vm.sendMessage(text)
    }
    
    private func askWhy(about rec: LessonRecommendation) {
        inputText = ""
        vm.sendMessage("Why do you recommend \"\(rec.lessonName)\" for \(rec.studentNames.joined(separator: " and "))?")
    }
}
