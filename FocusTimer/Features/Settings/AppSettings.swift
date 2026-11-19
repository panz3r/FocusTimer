import Foundation
import ServiceManagement

/// Area 4 Phase 4: display/integration app settings, extracted from the
/// former TimerViewModel god object. Session-behavior knobs (autoAdvance,
/// idle detection) live on SessionEngine — the machinery consumes them
/// directly.
///
/// Every property persists through didSet, exactly as before the split.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: UserDefaultsKeys.notificationsEnabled) }
    }
    @Published var showTaskLabelInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showTaskLabelInMenuBar, forKey: UserDefaultsKeys.showTaskLabelInMenuBar) }
    }
    @Published var notificationSound: NotificationSound {
        didSet { UserDefaults.standard.set(notificationSound.rawValue, forKey: UserDefaultsKeys.notificationSound) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            if launchAtLogin { try? SMAppService.mainApp.register() }
            else             { try? SMAppService.mainApp.unregister() }
        }
    }
    @Published var weeklyDigestEnabled: Bool {
        didSet {
            UserDefaults.standard.set(weeklyDigestEnabled, forKey: UserDefaultsKeys.weeklyDigestEnabled)
            if weeklyDigestEnabled { DigestChecker.shared.start() } else { DigestChecker.shared.stop() }
        }
    }
    @Published var weeklyBackupEnabled: Bool {
        didSet {
            UserDefaults.standard.set(weeklyBackupEnabled, forKey: UserDefaultsKeys.weeklyBackupEnabled)
            BackupScheduler.shared.restartIfNeeded()
        }
    }
    @Published var weeklyBackupMarkdownEnabled: Bool {
        didSet {
            UserDefaults.standard.set(weeklyBackupMarkdownEnabled, forKey: UserDefaultsKeys.weeklyBackupMarkdownEnabled)
        }
    }
    @Published var icloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(icloudSyncEnabled, forKey: UserDefaultsKeys.icloudSyncEnabled)
            SyncCoordinator.shared.restartIfNeeded()
        }
    }

    init() {
        let ud = UserDefaults.standard
        notificationsEnabled = ud.object(forKey: UserDefaultsKeys.notificationsEnabled) as? Bool ?? true
        showTaskLabelInMenuBar = ud.object(forKey: UserDefaultsKeys.showTaskLabelInMenuBar) as? Bool ?? false
        let soundRaw = ud.string(forKey: UserDefaultsKeys.notificationSound) ?? NotificationSound.systemDefault.rawValue
        notificationSound = NotificationSound(rawValue: soundRaw) ?? .systemDefault
        launchAtLogin = SMAppService.mainApp.status == .enabled
        weeklyDigestEnabled = ud.object(forKey: UserDefaultsKeys.weeklyDigestEnabled) as? Bool ?? true
        weeklyBackupEnabled = ud.object(forKey: UserDefaultsKeys.weeklyBackupEnabled) as? Bool ?? false
        weeklyBackupMarkdownEnabled = ud.object(forKey: UserDefaultsKeys.weeklyBackupMarkdownEnabled) as? Bool ?? false
        icloudSyncEnabled = ud.object(forKey: UserDefaultsKeys.icloudSyncEnabled) as? Bool ?? SyncCoordinator.iCloudDriveAvailable
    }
}
