import Contacts
import Foundation

struct DeviceContact: Identifiable, Sendable {
    let id: String           // CNContact identifier
    let displayName: String
    let phoneNumbers: [String]  // normalized E.164 strings, e.g. "+15551234567"
}

final class ContactsService: ObservableObject, @unchecked Sendable {

    @MainActor @Published var authorizationStatus: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)

    private let store = CNContactStore()

    // MARK: - Permission

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            let status = CNContactStore.authorizationStatus(for: .contacts)
            await MainActor.run { authorizationStatus = status }
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Fetch all contacts with phone numbers (runs off main thread)

    func fetchContacts() async -> [DeviceContact] {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return [] }

        return await Task.detached(priority: .userInitiated) { [store] in
            let keysToFetch: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactIdentifierKey as CNKeyDescriptor
            ]

            var contacts: [DeviceContact] = []
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)

            do {
                try store.enumerateContacts(with: request) { contact, _ in
                    let numbers = contact.phoneNumbers
                        .map { $0.value.stringValue }
                        .compactMap { ContactsService.normalizePhone($0) }

                    guard !numbers.isEmpty else { return }

                    let name = [contact.givenName, contact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                        .trimmingCharacters(in: .whitespaces)

                    contacts.append(DeviceContact(
                        id: contact.identifier,
                        displayName: name.isEmpty ? numbers[0] : name,
                        phoneNumbers: numbers
                    ))
                }
            } catch {
                // Permission denied or other error — return empty
            }

            return contacts
        }.value
    }

    // MARK: - Phone normalization

    /// Strips formatting and converts to E.164 (+1XXXXXXXXXX for US numbers).
    /// Returns nil if the result doesn't look like a valid number.
    static func normalizePhone(_ raw: String) -> String? {
        let digits = raw.filter { $0.isNumber }
        guard digits.count >= 7 else { return nil }

        // Already has country code
        if digits.count == 11 && digits.hasPrefix("1") {
            return "+" + digits
        }
        // 10-digit US number
        if digits.count == 10 {
            return "+1" + digits
        }
        // International (12+ digits starting with country code)
        if digits.count >= 12 {
            return "+" + digits
        }
        // Fallback — prefix + as-is
        return "+" + digits
    }
}
