import Foundation

/// Area 2 refactor: every UserDefaults key in one place.
///
/// Key stability matters: daily stats, the session log, schedules, and the
/// sync identifiers are read/written across app versions and (for iCloud
/// sync) across Macs — never rename an existing key's VALUE.
enum UserDefaultsKeys {

    // MARK: Legacy (pre-Area-4) settings — read by the schedule bootstrap
    // migration only; no longer written by the app.
    static let workDuration = "workDuration"
    static let shortBreakDuration = "shortBreakDuration"
    static let longBreakDuration = "longBreakDuration"
    static let sessionsBeforeLongBreak = "sessionsBeforeLongBreak"
    static let dailyGoal = "dailyGoal"

    // MARK: App settings
    static let notificationsEnabled = "notificationsEnabled"
    static let autoAdvance = "autoAdvance"
    static let showTaskLabelInMenuBar = "showTaskLabelInMenuBar"
    static let hotkeysEnabled = "hotkeysEnabled"
    static let notificationSound = "notificationSound"
    static let idleDetectionEnabled = "idleDetectionEnabled"
    static let idlePauseThreshold = "idlePauseThreshold"
    static let weeklyDigestEnabled = "weeklyDigestEnabled"
    static let weeklyBackupEnabled = "weeklyBackupEnabled"
    static let weeklyBackupMarkdownEnabled = "weeklyBackupMarkdownEnabled"
    static let icloudSyncEnabled = "icloudSyncEnabled"
    static let taskLabel = "taskLabel"

    // MARK: Global hotkeys
    static let toggleHotkeyLabel = "toggleHotkeyLabel"
    static let toggleHotkeyCode = "toggleHotkeyCode"
    static let toggleHotkeyMods = "toggleHotkeyMods"
    static let skipHotkeyLabel = "skipHotkeyLabel"
    static let skipHotkeyCode = "skipHotkeyCode"
    static let skipHotkeyMods = "skipHotkeyMods"

    // MARK: Stores (JSON blobs)
    static let dailyStatsStore = "v1_daily_stats"
    static let sessionLogStore = "v1_session_log"
    static let milestonesReached = "v1_milestones_reached"
    static let schedulesStore = "schedules.v1"
    static let schedulesActive = "schedules.active"

    // MARK: Sync (Area 3)
    static let socialConfig = "social.config"
    static let iCloudLastSyncAt = "icloud.lastSyncAt"
    static let syncDeviceId = "sync.deviceId"

    // MARK: Updates & backups
    static let updateApiURL = "update.apiURL"
    static let weeklyBackupFolderBookmark = "weeklyBackupFolderBookmark"
    static let weeklyBackupLastRunWeek = "weeklyBackupLastRunWeek"
    static let weeklyBackupLastRunAt = "weeklyBackupLastRunAt"
    static let lastDigestWeek = "lastDigestWeek"

    // MARK: Supabase (anonymous device auth)
    static let supabaseToken = "_sb_tok"
    static let supabaseUserId = "_sb_uid"
    static let supabaseDeviceId = "_sb_dev"
}
