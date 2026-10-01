#if os(macOS)
import SwiftUI
import AppKit
import Contacts
import ContactsUI

/// One email address or phone number from the guide's Contacts, offered while
/// they type into the Share your classroom sheet.
struct ContactAddressSuggestion: Identifiable, Hashable, Sendable {
    let name: String
    let address: String
    /// "home", "work", "mobile"…, or nil when the card has no label.
    let label: String?

    var id: String { "\(name)\u{1F}\(address)" }
}

/// Contacts lookups for the members sheet. Reads only; nothing from Contacts
/// is stored.
enum ContactAddressBook {
    nonisolated static var status: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    nonisolated static var canRead: Bool {
        status == .authorized
    }

    /// Asks once; later calls return the answer already given.
    static func requestAccess() async -> Bool {
        guard status == .notDetermined else { return canRead }
        return (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Every email address and phone number on the cards whose name matches
    /// `query`, people in name order.
    @concurrent
    static func suggestions(matching query: String, limit: Int = 6) async -> [ContactAddressSuggestion] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, !query.contains("@"), canRead else { return [] }
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor
        ]
        let contacts = (try? CNContactStore().unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: query),
            keysToFetch: keys
        )) ?? []

        var results: [ContactAddressSuggestion] = []
        for contact in contacts.sorted(by: { displayName(of: $0) < displayName(of: $1) }) {
            results += addresses(of: contact)
            if results.count >= limit { break }
        }
        return Array(results.prefix(limit))
    }

    nonisolated static func addresses(of contact: CNContact) -> [ContactAddressSuggestion] {
        let name = displayName(of: contact)
        let emails = contact.isKeyAvailable(CNContactEmailAddressesKey) ? contact.emailAddresses.map {
            ContactAddressSuggestion(name: name, address: $0.value as String, label: readableLabel($0.label))
        } : []
        let phones = contact.isKeyAvailable(CNContactPhoneNumbersKey) ? contact.phoneNumbers.map {
            ContactAddressSuggestion(name: name, address: $0.value.stringValue, label: readableLabel($0.label))
        } : []
        return emails + phones
    }

    nonisolated private static func displayName(of contact: CNContact) -> String {
        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        if !name.isEmpty { return name }
        return contact.isKeyAvailable(CNContactOrganizationNameKey) ? contact.organizationName : ""
    }

    nonisolated private static func readableLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        let readable = CNLabeledValue<NSString>.localizedString(forLabel: label)
        return readable.isEmpty ? nil : readable
    }
}

/// The address-book button beside the address field: opens the system
/// contact picker and hands back the email address or phone number the guide
/// clicks. `CNContactPicker` anchors to an `NSView`, hence the AppKit button.
struct ContactPickerButton: NSViewRepresentable {
    let onPick: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeNSView(context: Context) -> NSButton {
        let image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "Choose from Contacts")
            ?? NSImage()
        let button = NSButton(image: image, target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.bezelStyle = .push
        button.toolTip = "Choose from Contacts"
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onPick = onPick
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var onPick: (String) -> Void
        private var picker: CNContactPicker?

        init(onPick: @escaping (String) -> Void) {
            self.onPick = onPick
        }

        @objc func open(_ sender: NSButton) {
            Task {
                guard await ContactAddressBook.requestAccess() else {
                    ContactAddressBook.openPrivacySettings()
                    return
                }
                let picker = CNContactPicker()
                picker.displayedKeys = [CNContactEmailAddressesKey, CNContactPhoneNumbersKey]
                picker.delegate = self
                self.picker = picker
                picker.showRelative(to: sender.bounds, of: sender, preferredEdge: .maxY)
            }
        }

        // A click on one email address or phone number.
        func contactPicker(_ picker: CNContactPicker, didSelect contactProperty: CNContactProperty) {
            if let email = contactProperty.value as? String {
                choose(email)
            } else if let phone = contactProperty.value as? CNPhoneNumber {
                choose(phone.stringValue)
            }
        }

        // A click on the person rather than one of their addresses: take the
        // first email, else the first phone number.
        func contactPicker(_ picker: CNContactPicker, didSelect contact: CNContact) {
            if let first = ContactAddressBook.addresses(of: contact).first {
                choose(first.address)
            }
        }

        func contactPickerDidClose(_ picker: CNContactPicker) {
            self.picker = nil
        }

        private func choose(_ address: String) {
            onPick(address)
            picker?.close()
        }
    }
}

/// The matches under the address field; a click fills the field.
struct ContactSuggestionList: View {
    let suggestions: [ContactAddressSuggestion]
    let onPick: (ContactAddressSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    onPick(suggestion)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: suggestion.address.contains("@") ? "envelope" : "phone")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(suggestion.name)
                        Text(suggestion.address)
                            .foregroundStyle(.secondary)
                        if let label = suggestion.label {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(suggestion.name), \(suggestion.address)")
            }
        }
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
#endif
