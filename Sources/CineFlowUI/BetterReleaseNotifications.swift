import CineFlowCore
import CineFlowDesignSystem
import SwiftUI

public enum BetterReleaseNotificationTrigger: String, Codable, CaseIterable, Equatable, Sendable {
    case new4KRelease
    case betterSeededRelease
    case russianAudioAvailable
    case hdrVersionAvailable
    case healthierRelease

    public var title: String {
        switch self {
        case .new4KRelease:
            "New 4K release"
        case .betterSeededRelease:
            "Better seeded release"
        case .russianAudioAvailable:
            "Russian audio available"
        case .hdrVersionAvailable:
            "HDR version available"
        case .healthierRelease:
            "Healthier release"
        }
    }
}

public enum AppNotificationSeverity: String, Codable, CaseIterable, Equatable, Sendable {
    case informational
    case critical
}

public enum AppNotificationDestination: Codable, Equatable, Sendable {
    case home
    case library
    case lists
    case mediaDetail(String)
    case settingsSection(String)

    public var route: AppRoute {
        switch self {
        case .home:
            .home
        case .library:
            .library
        case .lists:
            .lists
        case .mediaDetail(let id):
            .mediaDetail(id: id)
        case .settingsSection(let id):
            .settingsSection(id: id)
        }
    }
}

public struct AppNotification: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let message: String
    public let category: NotificationCategory
    public let severity: AppNotificationSeverity
    public let destination: AppNotificationDestination
    public let mediaID: String
    public let mediaTitle: String
    public let releaseID: String
    public let triggers: [BetterReleaseNotificationTrigger]
    public let createdAt: Date
    public var isRead: Bool

    public var route: AppRoute {
        destination.route
    }

    public init(
        id: String,
        title: String,
        message: String,
        category: NotificationCategory,
        severity: AppNotificationSeverity = .informational,
        destination: AppNotificationDestination,
        mediaID: String = "",
        mediaTitle: String? = nil,
        releaseID: String = "",
        triggers: [BetterReleaseNotificationTrigger] = [],
        createdAt: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.category = category
        self.severity = severity
        self.destination = destination
        self.mediaID = mediaID
        self.mediaTitle = mediaTitle ?? title
        self.releaseID = releaseID
        self.triggers = triggers
        self.createdAt = createdAt
        self.isRead = isRead
    }

    public init(
        id: String? = nil,
        mediaID: String,
        mediaTitle: String,
        releaseID: String,
        triggers: [BetterReleaseNotificationTrigger],
        createdAt: Date = Date(),
        isRead: Bool = false
    ) {
        self.init(
            id: id ?? "better-release:\(mediaID)",
            title: triggers.first?.title ?? "Better release available",
            message: triggers.map(\.title).joined(separator: " · "),
            category: .betterRelease,
            severity: .informational,
            destination: .mediaDetail(mediaID),
            mediaID: mediaID,
            mediaTitle: mediaTitle,
            releaseID: releaseID,
            triggers: triggers,
            createdAt: createdAt,
            isRead: isRead
        )
    }
}

public typealias BetterReleaseNotification = AppNotification

public struct BetterReleaseSnapshot: Codable, Equatable, Sendable {
    public let bestReleaseID: String
    public let quality: ReleaseQuality
    public let seeders: Int
    public let hdr: HDRFormat
    public let hasRussianAudio: Bool
    public let healthScore: Double

    public init(release: TorrentRelease) {
        bestReleaseID = release.id
        quality = release.quality
        seeders = release.seeders
        hdr = release.hdr
        hasRussianAudio = release.audioLanguages.contains(where: Self.isRussianAudioLanguage)
        healthScore = release.releaseHealth.healthScore
    }

    private static func isRussianAudioLanguage(_ language: String) -> Bool {
        let normalized = language.lowercased()
        return normalized == "ru" || normalized == "rus" || normalized.contains("russian")
    }
}

public struct BetterReleaseNotificationDigest: Equatable, Sendable {
    public static let empty = BetterReleaseNotificationDigest(notifications: [], isDigestMode: true)

    public let notifications: [AppNotification]
    public let isDigestMode: Bool

    public init(notifications: [AppNotification], isDigestMode: Bool) {
        self.notifications = notifications
        self.isDigestMode = isDigestMode
    }
}

public protocol NotificationCenterStoreProtocol: Sendable {
    func notifications() async -> [AppNotification]
    func addNotification(_ notification: AppNotification) async
    func markRead(id: String) async
    func markAllRead() async
    func clearAll() async
}

public protocol BetterReleaseNotificationStoreProtocol: NotificationCenterStoreProtocol {
    func snapshot(mediaID: String) async -> BetterReleaseSnapshot?
    func setSnapshot(_ snapshot: BetterReleaseSnapshot, mediaID: String) async
    func hasNotified(mediaID: String) async -> Bool
    func markNotified(mediaID: String) async
}

public actor UserDefaultsNotificationCenterStore: BetterReleaseNotificationStoreProtocol {
    private let userDefaults: UserDefaults
    private let notificationsKey = "streamly.notificationCenter.notifications"
    private let legacyNotificationsKey = "streamly.betterRelease.notifications"
    private let snapshotsKey = "streamly.betterRelease.snapshots"
    private let notifiedMediaKey = "streamly.betterRelease.notifiedMediaIDs"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func notifications() async -> [AppNotification] {
        storedNotifications().sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity == .critical
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    public func addNotification(_ notification: AppNotification) async {
        var values = storedNotifications().filter { $0.id != notification.id }
        values.insert(notification, at: 0)
        saveNotifications(Array(values.prefix(200)))
    }

    public func markRead(id: String) async {
        let values = storedNotifications().map { notification in
            guard notification.id == id else { return notification }
            var updated = notification
            updated.isRead = true
            return updated
        }
        saveNotifications(values)
    }

    public func markAllRead() async {
        saveNotifications(storedNotifications().map { notification in
            var updated = notification
            updated.isRead = true
            return updated
        })
    }

    public func clearAll() async {
        userDefaults.removeObject(forKey: notificationsKey)
        userDefaults.removeObject(forKey: legacyNotificationsKey)
    }

    public func snapshot(mediaID: String) async -> BetterReleaseSnapshot? {
        storedSnapshots()[mediaID]
    }

    public func setSnapshot(_ snapshot: BetterReleaseSnapshot, mediaID: String) async {
        var values = storedSnapshots()
        values[mediaID] = snapshot
        if let data = try? JSONEncoder().encode(values) {
            userDefaults.set(data, forKey: snapshotsKey)
        }
    }

    public func hasNotified(mediaID: String) async -> Bool {
        Set(userDefaults.stringArray(forKey: notifiedMediaKey) ?? []).contains(mediaID)
    }

    public func markNotified(mediaID: String) async {
        var values = Set(userDefaults.stringArray(forKey: notifiedMediaKey) ?? [])
        values.insert(mediaID)
        userDefaults.set(Array(values).sorted(), forKey: notifiedMediaKey)
    }

    private func storedNotifications() -> [AppNotification] {
        if let data = userDefaults.data(forKey: notificationsKey),
           let values = try? JSONDecoder().decode([AppNotification].self, from: data) {
            return values
        }
        guard let legacyData = userDefaults.data(forKey: legacyNotificationsKey),
              let legacyValues = try? JSONDecoder().decode([AppNotification].self, from: legacyData) else {
            return []
        }
        saveNotifications(legacyValues)
        userDefaults.removeObject(forKey: legacyNotificationsKey)
        return legacyValues
    }

    private func saveNotifications(_ notifications: [AppNotification]) {
        if let data = try? JSONEncoder().encode(notifications) {
            userDefaults.set(data, forKey: notificationsKey)
        }
    }

    private func storedSnapshots() -> [String: BetterReleaseSnapshot] {
        guard let data = userDefaults.data(forKey: snapshotsKey),
              let values = try? JSONDecoder().decode([String: BetterReleaseSnapshot].self, from: data) else {
            return [:]
        }
        return values
    }
}

public typealias UserDefaultsBetterReleaseNotificationStore = UserDefaultsNotificationCenterStore

public actor InMemoryNotificationCenterStore: BetterReleaseNotificationStoreProtocol {
    private var storedNotifications: [AppNotification]
    private var snapshots: [String: BetterReleaseSnapshot]
    private var notifiedMediaIDs: Set<String>

    public init(
        notifications: [AppNotification] = [],
        snapshots: [String: BetterReleaseSnapshot] = [:],
        notifiedMediaIDs: Set<String> = []
    ) {
        storedNotifications = notifications
        self.snapshots = snapshots
        self.notifiedMediaIDs = notifiedMediaIDs
    }

    public func notifications() async -> [AppNotification] {
        storedNotifications.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity == .critical
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    public func addNotification(_ notification: AppNotification) async {
        storedNotifications.removeAll { $0.id == notification.id }
        storedNotifications.insert(notification, at: 0)
    }

    public func markRead(id: String) async {
        storedNotifications = storedNotifications.map { notification in
            guard notification.id == id else { return notification }
            var updated = notification
            updated.isRead = true
            return updated
        }
    }

    public func markAllRead() async {
        storedNotifications = storedNotifications.map { notification in
            var updated = notification
            updated.isRead = true
            return updated
        }
    }

    public func clearAll() async {
        storedNotifications.removeAll()
    }

    public func snapshot(mediaID: String) async -> BetterReleaseSnapshot? {
        snapshots[mediaID]
    }

    public func setSnapshot(_ snapshot: BetterReleaseSnapshot, mediaID: String) async {
        snapshots[mediaID] = snapshot
    }

    public func hasNotified(mediaID: String) async -> Bool {
        notifiedMediaIDs.contains(mediaID)
    }

    public func markNotified(mediaID: String) async {
        notifiedMediaIDs.insert(mediaID)
    }
}

public typealias InMemoryBetterReleaseNotificationStore = InMemoryNotificationCenterStore

public struct BetterReleaseNotificationService {
    private let libraryRepository: any LibraryRepositoryProtocol
    private let settingsRepository: any SettingsRepositoryProtocol
    private let store: any BetterReleaseNotificationStoreProtocol

    public init(
        libraryRepository: any LibraryRepositoryProtocol,
        settingsRepository: any SettingsRepositoryProtocol,
        store: any BetterReleaseNotificationStoreProtocol = UserDefaultsNotificationCenterStore()
    ) {
        self.libraryRepository = libraryRepository
        self.settingsRepository = settingsRepository
        self.store = store
    }

    public func scanForBetterReleases() async throws -> BetterReleaseNotificationDigest {
        let settings = await settingsRepository.appSettings.notifications
        guard settings.betterReleaseNotificationsEnabled, settings.isCategoryEnabled(.betterRelease) else {
            return BetterReleaseNotificationDigest(notifications: [], isDigestMode: settings.betterReleaseDigestMode)
        }

        let items = try await trackedItems()
        var notifications: [AppNotification] = []

        for item in items {
            guard let bestRelease = item.rankedReleases.first else { continue }
            let currentSnapshot = BetterReleaseSnapshot(release: bestRelease)

            guard let previousSnapshot = await store.snapshot(mediaID: item.id) else {
                await store.setSnapshot(currentSnapshot, mediaID: item.id)
                continue
            }
            await store.setSnapshot(currentSnapshot, mediaID: item.id)
            guard await store.hasNotified(mediaID: item.id) == false else { continue }

            let triggers = triggers(from: previousSnapshot, to: currentSnapshot)
            guard !triggers.isEmpty else { continue }

            let notification = AppNotification(
                mediaID: item.id,
                mediaTitle: item.displayTitle,
                releaseID: bestRelease.id,
                triggers: triggers
            )
            await store.addNotification(notification)
            await store.markNotified(mediaID: item.id)
            notifications.append(notification)
        }

        return BetterReleaseNotificationDigest(
            notifications: notifications.sorted { $0.createdAt > $1.createdAt },
            isDigestMode: settings.betterReleaseDigestMode
        )
    }

    private func trackedItems() async throws -> [MediaItem] {
        var itemsByID = Dictionary(uniqueKeysWithValues: (try await libraryRepository.items()).map { ($0.id, $0) })
        if let watchlist = try await libraryRepository.lists().first(where: { $0.isDefault }) {
            for item in try await libraryRepository.items(in: watchlist.id) {
                itemsByID[item.id] = item
            }
        }
        return itemsByID.values.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    private func triggers(from previous: BetterReleaseSnapshot, to current: BetterReleaseSnapshot) -> [BetterReleaseNotificationTrigger] {
        var triggers: [BetterReleaseNotificationTrigger] = []
        if previous.quality < .ultraHD, current.quality >= .ultraHD {
            triggers.append(.new4KRelease)
        }
        if (previous.hdr == .none || previous.hdr == .unknown), current.hdr != .none, current.hdr != .unknown {
            triggers.append(.hdrVersionAvailable)
        }
        if previous.hasRussianAudio == false, current.hasRussianAudio {
            triggers.append(.russianAudioAvailable)
        }
        if current.seeders > previous.seeders {
            triggers.append(.betterSeededRelease)
        }
        if current.healthScore > previous.healthScore {
            triggers.append(.healthierRelease)
        }
        return triggers
    }
}

@MainActor
public final class NotificationCenterViewModel: ObservableObject {
    @Published public private(set) var notifications: [AppNotification] = []
    @Published public private(set) var lastDigest = BetterReleaseNotificationDigest.empty

    private let store: any NotificationCenterStoreProtocol
    private let betterReleaseService: BetterReleaseNotificationService?
    private let settingsRepository: (any SettingsRepositoryProtocol)?

    public init(
        store: any NotificationCenterStoreProtocol = UserDefaultsNotificationCenterStore(),
        service: BetterReleaseNotificationService? = nil,
        settingsRepository: (any SettingsRepositoryProtocol)? = nil
    ) {
        self.store = store
        betterReleaseService = service
        self.settingsRepository = settingsRepository
    }

    public var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    public var criticalNotifications: [AppNotification] {
        notifications.filter { $0.severity == .critical }
    }

    public var informationalNotifications: [AppNotification] {
        notifications.filter { $0.severity == .informational }
    }

    public func notification(withID id: String) -> AppNotification? {
        notifications.first { $0.id == id }
    }

    public func load() async {
        if let betterReleaseService {
            lastDigest = (try? await betterReleaseService.scanForBetterReleases()) ?? .empty
        }
        let settings = await settingsRepository?.appSettings.notifications ?? NotificationSettings()
        notifications = await store.notifications()
            .filter { settings.isCategoryEnabled($0.category) }
            .filter { $0.category != .betterRelease || settings.betterReleaseNotificationsEnabled }
    }

    public func refresh() async {
        await load()
    }

    public func markRead(_ id: String) async {
        await store.markRead(id: id)
        await load()
    }

    public func ingest(_ digest: SeriesTrackingDigest) async {
        let settings = await settingsRepository?.appSettings.notifications ?? NotificationSettings()
        for item in digest.items {
            let notification = AppNotification(seriesTrackingNotification: item)
            guard settings.isCategoryEnabled(notification.category) else { continue }
            await store.addNotification(notification)
        }
        await load()
    }

    public func markAllRead() async {
        await store.markAllRead()
        await load()
    }

    public func clearAll() async {
        await store.clearAll()
        await load()
    }
}

public typealias BetterReleaseNotificationCenterViewModel = NotificationCenterViewModel

private extension AppNotification {
    init(seriesTrackingNotification notification: SeriesTrackingNotification) {
        let episode = notification.episode
        let title: String
        let message: String
        let category: NotificationCategory
        switch notification.kind {
        case .newEpisodeAvailable:
            title = "New episode"
            message = "\(episode.seriesTitle) S\(episode.episode.seasonNumber)E\(episode.episode.episodeNumber): \(episode.episode.title)"
            category = .newEpisode
        case .newReleaseFound:
            title = "Episode release available"
            message = "\(episode.seriesTitle) now has \(episode.availability.qualityLabel ?? "a playable") release."
            category = .newEpisode
        case .betterReleaseFound:
            title = "Better episode release"
            message = "\(episode.seriesTitle) has a better episode release available."
            category = .betterRelease
        }
        self.init(
            id: notification.id,
            title: title,
            message: message,
            category: category,
            severity: .informational,
            destination: .mediaDetail(episode.seriesID),
            mediaID: episode.seriesID,
            mediaTitle: episode.seriesTitle,
            releaseID: episode.availability.bestReleaseID ?? "",
            createdAt: episode.releasedAt ?? Date()
        )
    }
}

public struct NotificationCenterView: View {
    @ObservedObject private var viewModel: NotificationCenterViewModel
    private let open: (AppRoute) -> Void

    public init(viewModel: NotificationCenterViewModel, open: @escaping (AppRoute) -> Void) {
        self.viewModel = viewModel
        self.open = open
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            header

            if viewModel.notifications.isEmpty {
                EmptyState(
                    title: "No notifications",
                    message: "Important Streamly events will appear here.",
                    systemImage: "bell",
                    actionTitle: "Refresh",
                    actionSystemImage: "arrow.clockwise"
                ) {
                    Task { await viewModel.refresh() }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: CFSpacing.md) {
                        notificationGroup("Critical", notifications: viewModel.criticalNotifications)
                        notificationGroup("Info", notifications: viewModel.informationalNotifications)
                    }
                }
                .frame(maxHeight: 440)
            }
        }
        .padding(CFSpacing.lg)
        .frame(width: 440)
        .cfPanelBackground(fill: CFColors.panelFill)
        .task { await viewModel.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: CFSpacing.sm) {
            HStack {
                Text("Notifications")
                    .font(CFTypography.title)
                    .foregroundStyle(CFColors.textPrimary)
                Spacer()
                Text("\(viewModel.unreadCount) unread")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
            }

            HStack(spacing: CFSpacing.sm) {
                SecondaryButton("Mark all read", systemImage: "checkmark.circle") {
                    Task { await viewModel.markAllRead() }
                }
                .disabled(viewModel.unreadCount == 0)

                SecondaryButton("Clear all", systemImage: "trash") {
                    Task { await viewModel.clearAll() }
                }
                .disabled(viewModel.notifications.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func notificationGroup(_ title: String, notifications: [AppNotification]) -> some View {
        if !notifications.isEmpty {
            VStack(alignment: .leading, spacing: CFSpacing.sm) {
                Text(title)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
                    .textCase(.uppercase)

                ForEach(notifications) { notification in
                    notificationRow(notification)
                }
            }
        }
    }

    private func notificationRow(_ notification: AppNotification) -> some View {
        Button {
            Task { await viewModel.markRead(notification.id) }
            open(notification.route)
        } label: {
            HStack(alignment: .top, spacing: CFSpacing.md) {
                Image(systemName: iconName(for: notification))
                    .foregroundStyle(iconColor(for: notification))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.title)
                        .font(CFTypography.bodyEmphasis)
                        .foregroundStyle(CFColors.textPrimary)
                        .lineLimit(1)
                    Text(notification.message)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(CFSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                    .fill(notification.isRead ? CFColors.backgroundSecondary.opacity(0.45) : CFColors.activeFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                    .stroke(notification.severity == .critical ? CFColors.warning.opacity(0.45) : CFColors.separatorSubtle, lineWidth: CFSeparators.width)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconName(for notification: AppNotification) -> String {
        switch notification.category {
        case .betterRelease:
            "sparkles"
        case .newEpisode:
            "play.rectangle.on.rectangle"
        case .sync:
            notification.severity == .critical ? "icloud.slash" : "icloud.and.arrow.up"
        case .update:
            "arrow.down.circle"
        case .sourceAuth:
            "key.slash"
        case .cache:
            "externaldrive.badge.exclamationmark"
        case .announcement:
            "megaphone"
        }
    }

    private func iconColor(for notification: AppNotification) -> Color {
        if notification.isRead {
            return CFColors.textMuted
        }
        return notification.severity == .critical ? CFColors.warning : CFColors.accentPrimary
    }
}

public typealias BetterReleaseNotificationCenterView = NotificationCenterView
