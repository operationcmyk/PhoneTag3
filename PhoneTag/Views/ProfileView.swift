import SwiftUI

struct ProfileView: View {
    let user: User
    let authService: AuthService

    @Environment(\.dismiss) private var dismiss

    @State private var editingName = false
    @State private var newDisplayName = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var saveSuccess = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Account Info
                Section {
                    // Avatar
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 80, height: 80)
                            Text(String(user.displayName.prefix(1)).uppercased())
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.blue)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 8)
                } // avatar section

                Section("Account") {
                    // Display Name
                    LabeledContent("Name") {
                        Text(user.displayName)
                            .foregroundStyle(.secondary)
                    }

                    // Phone number — what was used to log in
                    LabeledContent("Phone") {
                        Text(user.phoneNumber ?? "—")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    // Firebase UID — useful for debugging "am I actually logged in?"
                    LabeledContent("User ID") {
                        Text(user.id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                // MARK: - Change Name
                Section {
                    Button {
                        newDisplayName = user.displayName
                        editingName = true
                    } label: {
                        Label("Change Display Name", systemImage: "pencil")
                    }
                }

                // MARK: - Sign Out
                Section {
                    Button(role: .destructive) {
                        authService.signOut()
                        dismiss()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("My Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
            .alert("Change Display Name", isPresented: $editingName) {
                TextField("Display name", text: $newDisplayName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                Button("Save") {
                    Task { await saveName() }
                }
                .disabled(newDisplayName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This is how other players see you.")
            }
            .alert("Error", isPresented: .constant(saveError != nil)) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .overlay {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    private func saveName() async {
        let trimmed = newDisplayName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != user.displayName else { return }
        isSaving = true
        do {
            try await authService.updateDisplayName(trimmed)
        } catch {
            saveError = "Couldn't update name: \(error.localizedDescription)"
        }
        isSaving = false
    }
}
