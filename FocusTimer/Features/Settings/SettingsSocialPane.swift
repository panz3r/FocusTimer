import SwiftUI

/// Social pane: provider selection (None / Supabase / Webhook), the
/// per-provider connection fields, the local identity, and the friend list.
/// The Social configuration state + bindings live here (they are only used
/// by this pane).
struct SocialPane: View {
    @State private var socialConfig = SocialConfig.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                SettingsRow("Provider") {
                    Picker("", selection: socialProvider) {
                        Text("None").tag(SocialConfig.Provider.none)
                        Text("Supabase").tag(SocialConfig.Provider.supabase)
                        Text("Webhook").tag(SocialConfig.Provider.webhook)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                if socialProvider.wrappedValue == .supabase {
                    Divider()
                    SettingsRow("Supabase URL") {
                        TextField("https://…supabase.co", text: supabaseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                    Divider()
                    SettingsRow("Anon key") {
                        SecureField("sb_publishable_…", text: anonKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                }
                if socialProvider.wrappedValue == .webhook {
                    Divider()
                    SettingsRow("Webhook URL") {
                        TextField("https://…", text: webhookURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                }
                if socialProvider.wrappedValue != .none {
                    Divider()
                    SettingsRow("Bearer token") {
                        SecureField("optional", text: bearerToken)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                    Divider()
                    SettingsRow("Username") {
                        TextField("you", text: socialUsername)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                            .autocorrectionDisabled()
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Friends (one per line, max 25)")
                            .font(.callout)
                        TextEditor(text: friendsText)
                            .font(.caption)
                            .frame(height: 56)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
            .settingsCard()

            if socialProvider.wrappedValue != .none {
                Text("Friend list is stored locally — make sure these usernames exist on the selected backend.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Bindings

    private var socialProvider: Binding<SocialConfig.Provider> {
        Binding(
            get: { socialConfig.provider },
            set: { socialConfig.provider = $0; saveSocialConfig() }
        )
    }

    private var supabaseURL: Binding<String> {
        Binding(
            get: { socialConfig.baseURL?.absoluteString ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                socialConfig.baseURL = trimmed.isEmpty ? nil : URL(string: trimmed)
                saveSocialConfig()
            }
        )
    }

    private var anonKey: Binding<String> {
        Binding(
            get: { socialConfig.anonKey ?? "" },
            set: { socialConfig.anonKey = $0.isEmpty ? nil : $0; saveSocialConfig() }
        )
    }

    private var webhookURL: Binding<String> {
        Binding(
            get: { socialConfig.baseURL?.absoluteString ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                socialConfig.baseURL = trimmed.isEmpty ? nil : URL(string: trimmed)
                saveSocialConfig()
            }
        )
    }

    private var bearerToken: Binding<String> {
        Binding(
            get: { socialConfig.bearerToken ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                socialConfig.bearerToken = trimmed.isEmpty ? nil : trimmed
                saveSocialConfig()
            }
        )
    }

    private var socialUsername: Binding<String> {
        Binding(
            get: { socialConfig.username ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespaces).lowercased()
                socialConfig.username = trimmed.isEmpty ? nil : trimmed
                saveSocialConfig()
            }
        )
    }

    private var friendsText: Binding<String> {
        Binding(
            get: { socialConfig.usernames.joined(separator: "\n") },
            set: {
                let names = $0
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
                socialConfig.usernames = Array(names.prefix(25))
                saveSocialConfig()
            }
        )
    }

    private func saveSocialConfig() {
        socialConfig.save()
    }
}
