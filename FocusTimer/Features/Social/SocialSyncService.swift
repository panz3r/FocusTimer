import Foundation

/// Area 4 Phase 4: pushes today's stats to the configured social backend.
/// Extracted from the former TimerViewModel — the engine now only signals
/// that a work session was recorded; this service handles the social side.
@MainActor
enum SocialSyncService {
    /// No-op when no backend is explicitly configured.
    static func pushTodayStats() async {
        let config = SocialConfig.load()
        let provider = SocialProviderRegistry.activeProvider(using: config)
        guard provider.isConfigured, config.isExplicitlyEnabled else { return }
        let stats = TodayStats(
            username: config.username ?? "",
            date: StatsStore.todayKey,
            sessions: StatsStore.shared.todaySessions,
            focusMinutes: StatsStore.shared.todayFocusMinutes,
            streak: StatsStore.shared.currentStreak,
            exportedAt: Date()
        )
        try? await provider.postTodayStats(stats)
    }
}
