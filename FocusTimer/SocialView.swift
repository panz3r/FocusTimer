import SwiftUI

struct SocialView: View {
    @StateObject private var vm = SocialViewModel()

    var body: some View {
        Group {
            switch vm.state {
            case .notConfigured: notConfiguredView
            case .loading:       loadingView
            case .setup:         setupView
            case .main:          mainView
            }
        }
        .frame(width: 380, height: 440)
        .onAppear { vm.load() }
    }

    // MARK: - States

    private var notConfiguredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "network.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Social is off")
                .font(.headline)
            Text("Connect a backend in Settings → Social,\nthen reopen this window.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Connecting…")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private var setupView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red)

            VStack(spacing: 6) {
                Text("Join the social layer")
                    .font(.title3.bold())
                Text("Pick a username so friends can find you.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }

            TextField("username", text: $vm.usernameInput)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .autocorrectionDisabled()
                .onSubmit { vm.createUsername() }

            if let err = vm.errorMessage {
                Text(err).foregroundStyle(.red).font(.caption)
            }

            Button("Get Started") { vm.createUsername() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(vm.isLoading || vm.usernameInput.trimmingCharacters(in: .whitespaces).isEmpty)

            if vm.isLoading { ProgressView().scaleEffect(0.7) }
        }
        .padding(32)
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            myHeader
            Divider()
            friendList
            Divider()
            addFriendBar
        }
    }

    // MARK: - Main sub-views

    private var myHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("@\(vm.myUsername)")
                    .font(.headline)
                HStack(spacing: 16) {
                    statPill("\(vm.todaySessions)", "sessions")
                    statPill("\(vm.todayMinutes)", "min")
                    statPill("\(vm.streak)", "day streak")
                }
            }
            Spacer()
            if vm.isLoading { ProgressView().scaleEffect(0.6) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func statPill(_ value: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(value).fontWeight(.semibold)
            Text(label).foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var friendList: some View {
        List {
            if vm.friends.isEmpty && !vm.isLoading {
                Text("No friends yet — add one below.")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .listRowSeparator(.hidden)
            }
            ForEach(vm.friends) { friend in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("@\(friend.username)")
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 12) {
                            Text("\(friend.sessions) sessions today")
                            Text("\(friend.focusMinutes) min")
                            Text("\(friend.streak)-day streak")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .onDelete { vm.removeFriends(at: $0) }
        }
        .listStyle(.plain)
    }

    private var addFriendBar: some View {
        VStack(spacing: 0) {
            if let err = vm.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                TextField("Add by username", text: $vm.addInput)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { vm.addFriend() }
                Button("Add") { vm.addFriend() }
                    .buttonStyle(.bordered)
                    .disabled(vm.addInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
    }
}

// MARK: - ViewModel

/// Friends are a local, username-based list stored in SocialConfig (max 25).
/// The configured SocialProvider resolves those usernames to current numbers.
/// Adding/removing friends never touches the network — only re-fetching does.
@MainActor
final class SocialViewModel: ObservableObject {
    enum State { case notConfigured, loading, setup, main }

    @Published var state: State = .loading
    @Published var myUsername = ""
    @Published var friends: [FriendStats] = []
    @Published var usernameInput = ""
    @Published var addInput = ""
    @Published var errorMessage: String?
    @Published var isLoading = false

    var todaySessions: Int    { StatsStore.shared.todaySessions    }
    var todayMinutes: Int     { StatsStore.shared.todayFocusMinutes }
    var streak: Int           { StatsStore.shared.currentStreak    }

    func load() {
        let config = SocialConfig.load()
        guard config.isExplicitlyEnabled else { state = .notConfigured; return }
        if let name = config.username?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            myUsername = name
            state = .main
            Task { await loadFriends() }
        } else {
            state = .setup
        }
    }

    func createUsername() {
        let name = usernameInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return }
        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            do {
                let config = SocialConfig.load()
                let provider = SocialProviderRegistry.activeProvider(using: config)
                // Supabase registers a profile row; webhook/none store locally.
                try await provider.registerUsername(name)
                var updated = config
                updated.username = name
                updated.save()
                myUsername = name
                state = .main
                await loadFriends()
            } catch let error as SocialError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func addFriend() {
        let name = addInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return }
        var config = SocialConfig.load()
        if name == config.username {
            errorMessage = "That's you!"
            return
        }
        if config.usernames.contains(name) {
            errorMessage = "Already in your list."
            return
        }
        guard config.usernames.count < 25 else {
            errorMessage = "Friend list is full (25 max)."
            return
        }
        config.usernames.append(name)
        config.save()
        addInput = ""
        errorMessage = nil
        Task { await loadFriends() }
    }

    func removeFriends(at offsets: IndexSet) {
        var config = SocialConfig.load()
        for index in offsets.sorted(by: >) where index < config.usernames.count {
            config.usernames.remove(at: index)
        }
        config.save()
        friends.remove(atOffsets: offsets)
    }

    func loadFriends() async {
        let config = SocialConfig.load()
        let provider = SocialProviderRegistry.activeProvider(using: config)
        guard provider.isConfigured, !config.usernames.isEmpty else {
            friends = []
            return
        }
        do {
            isLoading = true
            defer { isLoading = false }
            friends = try await provider.fetchFriendsStats(usernames: config.usernames)
        } catch {
            // Keep existing friend data on network failure
        }
    }
}
