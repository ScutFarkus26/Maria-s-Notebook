// OrderRequestDraftSheet.swift
// One email to the office asking for every item not yet requested. The guide
// picks the items, edits the wording, sends it through Mail (or copies it),
// and the items move to Asked For.

import SwiftUI
import CoreData
#if os(iOS)
import MessageUI
#endif

struct OrderRequestDraftSheet: View {
    /// The to-request items when the sheet opened.
    let items: [CDOrderItem]

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @Environment(\.dismiss) private var dismiss

    @SyncedAppStorage(OrderRequestPrefs.recipientNameKey) private var recipientName: String = ""
    @SyncedAppStorage(OrderRequestPrefs.recipientEmailKey) private var recipientEmail: String = ""
    @SyncedAppStorage(OrderRequestPrefs.signOffNameKey) private var signOffName: String = ""

    @State private var included: Set<NSManagedObjectID> = []
    @State private var subject = ""
    @State private var messageBody = ""
    /// The last text the sheet wrote itself. While the fields still hold it the
    /// guide hasn't edited them, so they follow the item toggles; once edited,
    /// they are left alone.
    @State private var lastGeneratedSubject = ""
    @State private var lastGeneratedBody = ""
    @State private var editingRecipient = false
    @State private var showingMailComposer = false
    @State private var confirmingSent = false
    @State private var sendErrorMessage: String?
    @State private var didCopy = false
    /// Bumped when a quantity changes. The quantities live on the managed
    /// objects, which this view doesn't observe, so the message reads this to
    /// know it must be rebuilt.
    @State private var quantityRevision = 0

    private var recipient: OrderRequestRecipient {
        OrderRequestRecipient(name: recipientName.trimmed(), email: recipientEmail.trimmed())
    }

    private var includedItems: [CDOrderItem] {
        items.filter { included.contains($0.objectID) }
    }

    private var lines: [OrderRequestLine] {
        _ = quantityRevision
        return includedItems.map(OrderRequestLine.init)
    }

    private var generatedSubject: String { OrderRequestMessage.subject(for: lines) }

    private var generatedBody: String {
        OrderRequestMessage.body(for: lines, recipientName: recipientName, signOff: signOffName)
    }

    private var itemCountText: String {
        includedItems.count == 1 ? "1 Item" : "\(includedItems.count) Items"
    }

    var body: some View {
        NavigationStack {
            Form {
                recipientSection
                itemsSection
                messageSection
                sendSection
            }
            .formStyle(.grouped)
            .navigationTitle("Order Request")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: start)
            .onChange(of: generatedSubject) { _, _ in followGeneratedText() }
            .onChange(of: generatedBody) { _, _ in followGeneratedText() }
            #if os(iOS)
            .sheet(isPresented: $showingMailComposer) {
                mailComposer
            }
            #endif
            .confirmationDialog(
                "Did the email send?",
                isPresented: $confirmingSent,
                titleVisibility: .visible
            ) {
                Button("Yes, Mark \(itemCountText) Asked For") { markAskedFor() }
                Button("Not Yet", role: .cancel) {}
            } message: {
                Text("Mail doesn't tell the app whether it went.")
            }
            .alert("Couldn't Open Mail", isPresented: .init(
                get: { sendErrorMessage != nil },
                set: { if !$0 { sendErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sendErrorMessage ?? "")
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
    }

    // MARK: - Sections

    @ViewBuilder
    private var recipientSection: some View {
        Section {
            if recipient.isConfigured && !editingRecipient {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipient.name.isEmpty ? recipient.email : recipient.name)
                            .font(.headline)
                        if !recipient.name.isEmpty {
                            Text(recipient.email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Change") { editingRecipient = true }
                }
            } else {
                OrderRequestSettingsView()
            }
        } header: {
            Text("To")
        } footer: {
            if !recipient.isConfigured {
                Text("Add the office's email to send. It's saved for next time.")
            }
        }
    }

    private var itemsSection: some View {
        Section {
            ForEach(items) { item in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayTitle)
                            .lineLimit(2)
                        if let caption = item.linkCaption {
                            Text(caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    OrderQuantityControl(quantity: Int(item.quantity)) { newValue in
                        OrderService.setQuantity(item, to: newValue)
                        saveCoordinator.save(viewContext, reason: "Order quantity")
                        quantityRevision += 1
                    }
                    Toggle("Include \(item.displayTitle)", isOn: includedBinding(for: item))
                        .labelsHidden()
                }
            }
        } header: {
            Text("Items")
        } footer: {
            Text("Anything you leave out stays under To Request.")
        }
    }

    private var messageSection: some View {
        Section {
            TextField("Subject", text: $subject)
            TextEditor(text: $messageBody)
                .font(.body)
                .frame(minHeight: 300)
            if messageBody != generatedBody || subject != generatedSubject {
                Button("Start Over from the Items") {
                    subject = generatedSubject
                    messageBody = generatedBody
                    lastGeneratedSubject = generatedSubject
                    lastGeneratedBody = generatedBody
                }
            }
        } header: {
            Text("Message")
        }
    }

    private var sendSection: some View {
        Section {
            Button(action: send) {
                Label("Send in Mail", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(includedItems.isEmpty || !recipient.isConfigured)

            Button {
                Pasteboard.copy(messageBody)
                didCopy = true
            } label: {
                Label(didCopy ? "Copied" : "Copy Message", systemImage: didCopy ? "checkmark" : "doc.on.doc")
            }
            .disabled(includedItems.isEmpty)

            Button {
                markAskedFor()
            } label: {
                Label("Mark \(itemCountText) Asked For", systemImage: OrderStage.requested.icon)
            }
            .disabled(includedItems.isEmpty)
        } footer: {
            Text("Once Mail sends it, the items move to Asked For. Sent it another way? "
                 + "Mark them asked for yourself.")
        }
    }

    private func includedBinding(for item: CDOrderItem) -> Binding<Bool> {
        Binding(
            get: { included.contains(item.objectID) },
            set: { isOn in
                if isOn {
                    included.insert(item.objectID)
                } else {
                    included.remove(item.objectID)
                }
            }
        )
    }

    // MARK: - Drafting

    private func start() {
        included = Set(items.map(\.objectID))
        subject = generatedSubject
        messageBody = generatedBody
        lastGeneratedSubject = subject
        lastGeneratedBody = messageBody
    }

    /// Rewrites whichever field the guide hasn't touched since the sheet last wrote it.
    private func followGeneratedText() {
        if subject == lastGeneratedSubject { subject = generatedSubject }
        if messageBody == lastGeneratedBody { messageBody = generatedBody }
        lastGeneratedSubject = generatedSubject
        lastGeneratedBody = generatedBody
        didCopy = false
    }

}

// MARK: - Sending

extension OrderRequestDraftSheet {

    private func markAskedFor() {
        let asked = includedItems
        guard !asked.isEmpty else { return }
        OrderService.markRequested(asked, from: recipient.label)
        saveCoordinator.save(viewContext, reason: "Mark order request asked for")
        dismiss()
    }

    #if os(iOS)
    private var mailComposer: some View {
        MailComposerView(
            toRecipients: recipient.emails,
            subject: subject,
            body: messageBody,
            preferredSender: AttendanceEmail.storedFromAddress()
        ) { result, _ in
            showingMailComposer = false
            if result == .sent {
                markAskedFor()
            }
        }
    }

    private func send() {
        if MFMailComposeViewController.canSendMail() {
            showingMailComposer = true
        } else if let url = AttendanceEmail.makeMailtoURL(
            to: recipient.emails,
            subject: subject,
            body: messageBody
        ) {
            UIApplication.shared.open(url)
            confirmingSent = true
        } else {
            sendErrorMessage = "No mail account is set up on this device. Copy the message instead."
        }
    }
    #elseif os(macOS)
    private func send() {
        MacOSMailSender.send(
            to: recipient.emails.joined(separator: ", "),
            subject: subject,
            body: messageBody
        ) { success in
            if success {
                markAskedFor()
            } else {
                // The compose window may still have opened; let the guide say.
                confirmingSent = true
            }
        }
    }
    #else
    private func send() {
        sendErrorMessage = "Mail isn't available here. Copy the message instead."
    }
    #endif
}
