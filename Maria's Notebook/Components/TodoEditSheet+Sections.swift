// swiftlint:disable file_length
import SwiftUI
import SwiftData

extension TodoEditSheet {
    // MARK: - Due Date Section
    @ViewBuilder
    var dueDateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack {
                Text("When")
                    .font(AppTheme.ScaledFont.body)
                Spacer()
                TodoSchedulePickerButton(
                    scheduledDate: $scheduledDate,
                    dueDate: $deadlineDate,
                    isSomeday: $isSomeday
                )
            }

            Picker("Repeats", selection: $recurrence) {
                ForEach(RecurrencePattern.allCases, id: \.self) { pattern in
                    Text(pattern.rawValue).tag(pattern)
                }
            }
            .pickerStyle(.menu)

            if recurrence != .none {
                Toggle("Repeat after completion", isOn: $repeatAfterCompletion)
                    .font(AppTheme.ScaledFont.body)
                if recurrence == .custom {
                    Stepper("Every \(customIntervalDays) days", value: $customIntervalDays, in: 1...365)
                        .font(AppTheme.ScaledFont.body)
                }
            }
        }
    }

    // MARK: - Priority Section
    @ViewBuilder
    var prioritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Priority")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: 8) {
                ForEach(TodoPriority.allCases, id: \.self) { priorityLevel in
                    Button {
                        adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            priority = priorityLevel
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: priorityLevel.icon)
                                .font(.system(size: 12))
                            Text(priorityLevel.rawValue)
                                .font(AppTheme.ScaledFont.body)
                                .fontWeight(priority == priorityLevel ? .semibold : .regular)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    priority == priorityLevel
                                        ? colorForPriority(priorityLevel).opacity(0.15)
                                        : Color.secondary.opacity(0.1)
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    priority == priorityLevel
                                        ? colorForPriority(priorityLevel).opacity(0.4)
                                        : Color.clear,
                                    lineWidth: 1.5
                                )
                        }
                        .foregroundStyle(priority == priorityLevel ? colorForPriority(priorityLevel) : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func colorForPriority(_ priority: TodoPriority) -> Color {
        switch priority {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    // MARK: - Recurrence Section
    @ViewBuilder
    var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Repeat")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                if recurrence != .none {
                    Image(systemName: recurrence.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                }
            }

            Menu {
                ForEach(RecurrencePattern.allCases, id: \.self) { pattern in
                    Button {
                        adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            recurrence = pattern
                        }
                    } label: {
                        HStack {
                            Text(pattern.description)
                            if recurrence == pattern {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(recurrence.description)
                        .font(AppTheme.ScaledFont.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(!hasDueDate)
            .opacity(hasDueDate ? 1.0 : 0.5)

            if !hasDueDate {
                Text("Set a due date to enable recurrence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Subtasks Section
    @ViewBuilder
    var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Checklist")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                if !(todo.subtasks ?? []).isEmpty {
                    Text(todo.subtasksProgressText ?? "")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                }

                Button {
                    addSubtask()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }

            if (todo.subtasks ?? []).isEmpty {
                Text("No checklist items")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .padding(.vertical, 8)
            } else {
                let sortedSubtasks = (todo.subtasks ?? []).sorted(by: { $0.orderIndex < $1.orderIndex })
                VStack(spacing: 6) {
                    ForEach(sortedSubtasks) { subtask in
                        SubtaskRow(
                            subtask: subtask,
                            onToggle: { toggleSubtask(subtask) },
                            onDelete: { deleteSubtask(subtask) },
                            onUpdate: { newTitle in updateSubtask(subtask, title: newTitle) }
                        )
                    }
                    .onMove { source, destination in
                        reorderSubtasks(from: source, to: destination)
                    }
                }
            }
        }
    }

    // MARK: - Work Integration Section
    @ViewBuilder
    var workIntegrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Work Integration")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            if todo.linkedWorkItemID != nil {
                HStack(spacing: 10) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.indigo)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Linked to Work Item")
                            .font(AppTheme.ScaledFont.bodySemibold)
                        Text("This todo is connected to a work item")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        todo.linkedWorkItemID = nil
                        if let context = todo.modelContext {
                            do {
                                try context.save()
                            } catch {
                                print("\u{26A0}\u{FE0F} [\(#function)] Failed to save todo: \(error)")
                            }
                        }
                    } label: {
                        Text("Unlink")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(AppColors.destructive)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.indigo.opacity(0.1))
                .cornerRadius(8)
            } else {
                Button {
                    createWorkItemFromTodo()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text("Create Work Item")
                            .font(AppTheme.ScaledFont.bodySemibold)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Text("Convert this todo into a work item for tracking")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Attachments Section
    @ViewBuilder
    var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Attachments")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Button {
                    isShowingFileImporter = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.brown)
                }
                .buttonStyle(.plain)
            }

            if todo.attachmentPaths.isEmpty {
                Text("No attachments")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(todo.attachmentPaths.enumerated()), id: \.offset) { index, path in
                        HStack(spacing: 10) {
                            Image(systemName: fileIcon(for: path))
                                .font(.system(size: 20))
                                .foregroundStyle(.brown)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(fileName(from: path))
                                    .font(AppTheme.ScaledFont.body)
                                    .lineLimit(1)
                                Text(fileSize(for: path))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                removeAttachment(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let url = URL(fileURLWithPath: path)
                            if FileManager.default.fileExists(atPath: path) {
                                previewingAttachmentURL = url
                            }
                        }
                    }
                }
            }

            Text("Tap + to attach files or images")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Time Estimate Section
    @ViewBuilder
    var timeEstimateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time Tracking")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(spacing: 16) {
                // Estimated Time
                VStack(alignment: .leading, spacing: 8) {
                    Text("Estimated Time")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        // Hours picker
                        HStack(spacing: 8) {
                            #if os(macOS)
                            Picker("", selection: $estimatedHours) {
                                ForEach(0..<24) { hour in
                                    Text("\(hour)").tag(hour)
                                }
                            }
                            .frame(width: 60)
                            #else
                            Picker("Hours", selection: $estimatedHours) {
                                ForEach(0..<24) { hour in
                                    Text("\(hour) hr").tag(hour)
                                }
                            }
                            .pickerStyle(.menu)
                            #endif

                            Text("hours")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // Minutes picker
                        HStack(spacing: 8) {
                            #if os(macOS)
                            Picker("", selection: $estimatedMinutes) {
                                ForEach([0, 15, 30, 45], id: \.self) { minute in
                                    Text("\(minute)").tag(minute)
                                }
                            }
                            .frame(width: 60)
                            #else
                            Picker("Minutes", selection: $estimatedMinutes) {
                                ForEach([0, 15, 30, 45], id: \.self) { minute in
                                    Text("\(minute) min").tag(minute)
                                }
                            }
                            .pickerStyle(.menu)
                            #endif

                            Text("min")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Clear button
                        if estimatedHours > 0 || estimatedMinutes > 0 {
                            Button {
                                estimatedHours = 0
                                estimatedMinutes = 0
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(10)

                // Actual Time
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actual Time")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        // Hours picker
                        HStack(spacing: 8) {
                            #if os(macOS)
                            Picker("", selection: $actualHours) {
                                ForEach(0..<24) { hour in
                                    Text("\(hour)").tag(hour)
                                }
                            }
                            .frame(width: 60)
                            #else
                            Picker("Hours", selection: $actualHours) {
                                ForEach(0..<24) { hour in
                                    Text("\(hour) hr").tag(hour)
                                }
                            }
                            .pickerStyle(.menu)
                            #endif

                            Text("hours")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // Minutes picker
                        HStack(spacing: 8) {
                            #if os(macOS)
                            Picker("", selection: $actualMinutes) {
                                ForEach([0, 15, 30, 45], id: \.self) { minute in
                                    Text("\(minute)").tag(minute)
                                }
                            }
                            .frame(width: 60)
                            #else
                            Picker("Minutes", selection: $actualMinutes) {
                                ForEach([0, 15, 30, 45], id: \.self) { minute in
                                    Text("\(minute) min").tag(minute)
                                }
                            }
                            .pickerStyle(.menu)
                            #endif

                            Text("min")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Clear button
                        if actualHours > 0 || actualMinutes > 0 {
                            Button {
                                actualHours = 0
                                actualMinutes = 0
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .background(Color.green.opacity(0.08))
                .cornerRadius(10)

                // Time variance display
                if estimatedHours > 0 || estimatedMinutes > 0 || actualHours > 0 || actualMinutes > 0 {
                    let estimatedTotal = estimatedHours * 60 + estimatedMinutes
                    let actualTotal = actualHours * 60 + actualMinutes
                    let variance = actualTotal - estimatedTotal

                    HStack(spacing: 8) {
                        let varianceIcon = variance > 0
                            ? "exclamationmark.triangle.fill"
                            : variance < 0 ? "checkmark.circle.fill" : "equal.circle.fill"
                        Image(systemName: varianceIcon)
                            .foregroundStyle(variance > 0 ? .orange : variance < 0 ? .green : .blue)

                        if variance == 0 && actualTotal > 0 {
                            Text("On track")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if variance > 0 {
                            Text("Over by \(formatMinutes(variance))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if variance < 0 {
                            Text("Under by \(formatMinutes(abs(variance)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }

    // MARK: - Reminder Section
    @ViewBuilder
    var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reminder")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Toggle("", isOn: $hasReminder)
                    .labelsHidden()
            }

            if hasReminder {
                VStack(spacing: 12) {
                    DatePicker(
                        "Remind me at",
                        selection: $reminderDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)

                    if isSchedulingNotification {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scheduling notification...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Show reminder info
                    HStack(spacing: 8) {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(formatReminderDate(reminderDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                }
            } else {
                Text("No reminder set")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }

    func formatReminderDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today at' h:mm a"
        } else if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "'Tomorrow at' h:mm a"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE 'at' h:mm a"
        } else {
            formatter.dateFormat = "MMM d 'at' h:mm a"
        }

        return formatter.string(from: date)
    }

    // MARK: - Mood & Reflection Section
    @ViewBuilder
    var moodReflectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mood & Reflection")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            // Mood selection
            VStack(alignment: .leading, spacing: 8) {
                Text("How are you feeling about this task?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                    ForEach(TodoMood.allCases, id: \.self) { mood in
                        Button {
                            if selectedMood == mood {
                                selectedMood = nil // Deselect if already selected
                            } else {
                                selectedMood = mood
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(mood.emoji)
                                    .font(.title2)
                                Text(mood.rawValue)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                selectedMood == mood
                                    ? mood.color.opacity(0.2)
                                    : Color.primary.opacity(0.04)
                            )
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        selectedMood == mood ? mood.color : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Reflection notes
            VStack(alignment: .leading, spacing: 8) {
                Text("Reflection Notes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $reflectionNotes)
                    .font(AppTheme.ScaledFont.body)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                    .scrollContentBackground(.hidden)

                Text("Personal thoughts, lessons learned, or context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Location Reminder Section
    @ViewBuilder
    var locationReminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Location Reminder")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Toggle("", isOn: $hasLocationReminder)
                    .labelsHidden()
            }

            if hasLocationReminder {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        TextField("Location name (e.g., School, Home)", text: $locationName)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            isShowingMapPicker = true
                        } label: {
                            Image(systemName: "map")
                                .font(.system(size: 16))
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                    if let lat = locationLatitude, let lon = locationLongitude {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.red)
                            Text(String(format: "%.4f, %.4f", lat, lon))
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                locationLatitude = nil
                                locationLongitude = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Toggle("Notify on arrival", isOn: $notifyOnEntry)
                        Spacer()
                    }

                    HStack {
                        Toggle("Notify on departure", isOn: $notifyOnExit)
                        Spacer()
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(10)
            } else {
                Text("Set a location-based reminder for this task")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $isShowingMapPicker) {
            TodoLocationPickerView(
                locationName: $locationName,
                latitude: $locationLatitude,
                longitude: $locationLongitude
            )
        }
    }

    // MARK: - Section Helper Functions

    func fileIcon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "gif":
            return "photo"
        case "pdf":
            return "doc.fill"
        case "doc", "docx":
            return "doc.text.fill"
        case "txt":
            return "doc.plaintext"
        default:
            return "doc.fill"
        }
    }

    func fileName(from path: String) -> String {
        (path as NSString).lastPathComponent
    }

    func fileSize(for path: String) -> String {
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try FileManager.default.attributesOfItem(atPath: path)
        } catch {
            print("\u{26A0}\u{FE0F} [\(#function)] Failed to get file attributes: \(error)")
            return "Unknown size"
        }
        guard let size = attrs[.size] as? Int64 else {
            return "Unknown size"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    func removeAttachment(at index: Int) {
        guard index < todo.attachmentPaths.count else { return }
        todo.attachmentPaths.remove(at: index)
        if let context = todo.modelContext {
            do {
                try context.save()
            } catch {
                print("\u{26A0}\u{FE0F} [\(#function)] Failed to save todo: \(error)")
            }
        }
    }

    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let documentsDir = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first else { return }
            let attachmentsDir = documentsDir.appendingPathComponent("TodoAttachments", isDirectory: true)

            try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                let destURL = attachmentsDir.appendingPathComponent(url.lastPathComponent)
                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: url, to: destURL)
                    todo.attachmentPaths.append(destURL.path)
                } catch {
                    print("\u{26A0}\u{FE0F} [\(#function)] Failed to copy attachment: \(error)")
                }
            }

            if let context = todo.modelContext {
                do {
                    try context.save()
                } catch {
                    print("\u{26A0}\u{FE0F} [\(#function)] Failed to save attachments: \(error)")
                }
            }
        case .failure(let error):
            print("\u{26A0}\u{FE0F} [\(#function)] File import failed: \(error)")
        }
    }

    func createWorkItemFromTodo() {
        guard let context = todo.modelContext else { return }

        // Create a new work model from this todo
        let work = WorkModel()
        work.title = todo.title
        work.setLegacyNoteText(todo.notes, in: context)
        work.dueAt = todo.dueDate

        // Assign to first student if available
        if let firstStudentID = todo.studentIDs.first {
            work.studentID = firstStudentID
        }

        context.insert(work)

        // Link the work to this todo
        todo.linkedWorkItemID = work.id.uuidString

        do {
            try context.save()
        } catch {
            print("\u{26A0}\u{FE0F} [\(#function)] Failed to link work item: \(error)")
        }
    }

    func addSubtask() {
        let newSubtask = TodoSubtask(
            title: "",
            orderIndex: (todo.subtasks ?? []).count
        )
        if todo.subtasks == nil { todo.subtasks = [] }
        todo.subtasks?.append(newSubtask)
        if let context = todo.modelContext {
            do {
                try context.save()
            } catch {
                print("\u{26A0}\u{FE0F} [\(#function)] Failed to save subtask: \(error)")
            }
        }
    }

    func toggleSubtask(_ subtask: TodoSubtask) {
        subtask.isCompleted.toggle()
        if subtask.isCompleted {
            subtask.completedAt = Date()
        } else {
            subtask.completedAt = nil
        }
        if let context = todo.modelContext {
            do {
                try context.save()
            } catch {
                print("\u{26A0}\u{FE0F} [\(#function)] Failed to toggle subtask: \(error)")
            }
        }
    }

    func deleteSubtask(_ subtask: TodoSubtask) {
        if let context = todo.modelContext {
            context.delete(subtask)
            do {
                try context.save()
            } catch {
                print("\u{26A0}\u{FE0F} [\(#function)] Failed to delete subtask: \(error)")
            }
        }
    }

    func updateSubtask(_ subtask: TodoSubtask, title: String) {
        subtask.title = title
        if let context = todo.modelContext {
            do {
                try context.save()
            } catch {
                print("\u{26A0}\u{FE0F} [\(#function)] Failed to update subtask: \(error)")
            }
        }
    }

    func reorderSubtasks(from source: IndexSet, to destination: Int) {
        var sorted = (todo.subtasks ?? []).sorted(by: { $0.orderIndex < $1.orderIndex })
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, subtask) in sorted.enumerated() {
            subtask.orderIndex = index
        }
        if let context = todo.modelContext {
            do {
                try context.save()
            } catch {
                print("\u{26A0}\u{FE0F} [\(#function)] Failed to reorder subtasks: \(error)")
            }
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func formatTodoForSharing() -> String {
        var text = "\u{1F4CB} \(title.trimmingCharacters(in: .whitespacesAndNewlines))\n"

        // Priority
        if priority != .none {
            let priorityEmoji = priority == .high ? "\u{1F534}" : priority == .medium ? "\u{1F7E0}" : "\u{1F535}"
            text += "\(priorityEmoji) Priority: \(priority.rawValue)\n"
        }

        // Due date
        if hasDueDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            text += "\u{1F4C5} Due: \(formatter.string(from: dueDate))\n"
        }

        // Assigned students
        if !selectedStudentIDs.isEmpty {
            let assignedStudents = students.filter { selectedStudentIDs.contains($0.id.uuidString) }
            let names = assignedStudents.map { $0.firstName }.joined(separator: ", ")
            text += "\u{1F465} Assigned to: \(names)\n"
        }

        // Reminder
        if hasReminder {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            text += "\u{1F514} Reminder: \(formatter.string(from: reminderDate))\n"
        }

        // Time estimate
        let totalEstimated = estimatedHours * 60 + estimatedMinutes
        if totalEstimated > 0 {
            let hours = totalEstimated / 60
            let mins = totalEstimated % 60
            if hours > 0 && mins > 0 {
                text += "\u{23F1}\u{FE0F} Estimated time: \(hours)h \(mins)m\n"
            } else if hours > 0 {
                text += "\u{23F1}\u{FE0F} Estimated time: \(hours)h\n"
            } else {
                text += "\u{23F1}\u{FE0F} Estimated time: \(mins)m\n"
            }
        }

        // Mood
        if let mood = selectedMood {
            text += "\(mood.emoji) Mood: \(mood.rawValue)\n"
        }

        // Reflection
        let trimmedReflection = reflectionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedReflection.isEmpty {
            text += "\u{1F4AD} Reflection: \(trimmedReflection)\n"
        }

        // Subtasks
        let detailSubs = todo.subtasks ?? []
        if !detailSubs.isEmpty {
            text += "\n\u{2705} Subtasks (\(detailSubs.filter { $0.isCompleted }.count)/\(detailSubs.count)):\n"
            for subtask in detailSubs.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                let checkbox = subtask.isCompleted ? "\u{2611}\u{FE0F}" : "\u{2610}"
                text += "  \(checkbox) \(subtask.title)\n"
            }
        }

        // Notes
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            text += "\n\u{1F4DD} Notes:\n\(trimmedNotes)\n"
        }

        return text
    }

    func saveAsTemplate() {
        guard !templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let context = todo.modelContext else {
            templateName = ""
            return
        }

        let trimmedName = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalEstimated = estimatedHours * 60 + estimatedMinutes
        let selectedNames = students
            .filter { selectedStudentIDs.contains($0.id.uuidString) }
            .map(\.fullName)
        let syncedTemplateTags = TodoTagHelper.syncStudentTags(
            existingTags: todo.tags,
            studentNames: selectedNames
        )

        let template = TodoTemplate(
            name: trimmedName,
            title: title,
            notes: notes,
            priority: priority,
            defaultEstimatedMinutes: totalEstimated > 0 ? totalEstimated : nil,
            defaultStudentIDs: Array(selectedStudentIDs),
            tags: syncedTemplateTags
        )

        context.insert(template)
        do {
            try context.save()
        } catch {
            print("\u{26A0}\u{FE0F} [\(#function)] Failed to save template: \(error)")
        }

        templateName = ""
    }

    // swiftlint:disable:next function_body_length
    func save() {
        todo.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        todo.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        todo.studentIDs = Array(selectedStudentIDs)
        let selectedNames = students
            .filter { selectedStudentIDs.contains($0.id.uuidString) }
            .map(\.fullName)
        todo.tags = TodoTagHelper.syncStudentTags(
            existingTags: todo.tags,
            studentNames: selectedNames
        )
        todo.scheduledDate = scheduledDate
        todo.dueDate = deadlineDate
        todo.isSomeday = isSomeday
        todo.priority = priority
        todo.recurrence = recurrence
        todo.repeatAfterCompletion = recurrence != .none ? repeatAfterCompletion : false
        todo.customIntervalDays = recurrence == .custom ? customIntervalDays : nil

        // Save time estimates
        let totalEstimated = estimatedHours * 60 + estimatedMinutes
        let totalActual = actualHours * 60 + actualMinutes
        todo.estimatedMinutes = totalEstimated > 0 ? totalEstimated : nil
        todo.actualMinutes = totalActual > 0 ? totalActual : nil

        // Save mood and reflection
        todo.mood = selectedMood
        todo.reflectionNotes = reflectionNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Save location reminder
        if hasLocationReminder && !locationName.isEmpty {
            todo.locationName = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
            todo.notifyOnEntry = notifyOnEntry
            todo.notifyOnExit = notifyOnExit
            // Note: Actual coordinates would be set via location picker in full implementation
        } else {
            todo.locationName = nil
            todo.locationLatitude = nil
            todo.locationLongitude = nil
        }

        // Handle reminder notification
        Task {
            if hasReminder {
                isSchedulingNotification = true
                do {
                    try await TodoNotificationService.shared.scheduleNotification(for: todo, at: reminderDate)
                } catch {
                    print("Error scheduling notification: \(error)")
                }
                isSchedulingNotification = false
            } else {
                // Cancel notification if reminder was disabled
                TodoNotificationService.shared.cancelNotification(for: todo)
            }

            if let context = todo.modelContext {
                do {
                    try context.save()
                } catch {
                    print("\u{26A0}\u{FE0F} [\(#function)] Failed to save todo: \(error)")
                }
            }

            closeEditor()
        }
    }

    func closeEditor() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }
}
