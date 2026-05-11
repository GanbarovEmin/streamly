import CineFlowCore
import CineFlowDesignSystem
import Foundation

public enum WatchHistoryState: Equatable, Sendable {
    case loading
    case loaded
    case empty
    case failed(String)
}

public enum WatchHistoryFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case movies
    case series

    public var id: String { rawValue }
}

public struct WatchHistoryDateGroup: Identifiable, Equatable, Sendable {
    public let id: Date
    public let title: String
    public let entries: [WatchHistoryItem]
}

@MainActor
public final class ContinueWatchingViewModel: ObservableObject {
    @Published public private(set) var state: WatchHistoryState = .loading
    @Published public private(set) var items: [PlaybackProgress] = []

    private let repository: any PlaybackProgressRepositoryProtocol

    public init(repository: any PlaybackProgressRepositoryProtocol) {
        self.repository = repository
    }

    public func load() async {
        state = .loading
        do {
            items = try await repository.continueWatching(includeCompleted: false)
            state = items.isEmpty ? .empty : .loaded
        } catch {
            items = []
            state = .failed(CineFlowError.from(error, fallbackCategory: .database).userMessage)
        }
    }

    public func clear(_ progress: PlaybackProgress) async {
        try? await repository.clearProgress(mediaID: progress.mediaID, episodeID: progress.episodeID)
        await load()
    }

    public func cardModel(for progress: PlaybackProgress) -> CFMediaCardModel {
        CFMediaCardModel(
            id: progress.episodeID ?? progress.mediaID,
            title: title(for: progress),
            metadata: "\(Int(progress.progressPercent.rounded()))% · \(timeLabel(progress.positionSeconds))",
            badge: nil,
            progress: progress.progressPercent / 100,
            accentIndex: abs((progress.episodeID ?? progress.mediaID).hashValue)
        )
    }

    private func title(for progress: PlaybackProgress) -> String {
        if progress.mediaID.contains(":tv:") {
            return progress.episodeID == nil ? "Сериал" : "Серия"
        }
        return "Фильм"
    }

    private func timeLabel(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds.rounded())) / 60
        return "\(minutes)m watched"
    }
}

@MainActor
public final class WatchHistoryViewModel: ObservableObject {
    @Published public private(set) var state: WatchHistoryState = .loading
    @Published public private(set) var entries: [WatchHistoryItem] = []
    @Published public private(set) var selectedFilter: WatchHistoryFilter = .all

    private let repository: any WatchHistoryRepositoryProtocol

    public init(repository: any WatchHistoryRepositoryProtocol) {
        self.repository = repository
    }

    public var visibleEntries: [WatchHistoryItem] {
        entries.filter { entry in
            switch selectedFilter {
            case .all:
                return true
            case .movies:
                return !entry.mediaID.contains(":tv:")
            case .series:
                return entry.mediaID.contains(":tv:") || entry.episodeID != nil
            }
        }
    }

    public var groups: [WatchHistoryDateGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleEntries) { entry in
            calendar.startOfDay(for: entry.lastWatchedAt)
        }

        return grouped.keys.sorted(by: >).map { day in
            WatchHistoryDateGroup(
                id: day,
                title: dateTitle(day),
                entries: grouped[day, default: []].sorted { $0.lastWatchedAt > $1.lastWatchedAt }
            )
        }
    }

    public func load() async {
        state = .loading
        do {
            entries = try await repository.entries(limit: 500)
            state = entries.isEmpty ? .empty : .loaded
        } catch {
            entries = []
            state = .failed(CineFlowError.from(error, fallbackCategory: .database).userMessage)
        }
    }

    public func setFilter(_ filter: WatchHistoryFilter) {
        selectedFilter = filter
    }

    public func clearHistory() async {
        do {
            try await repository.clear()
            entries = []
            state = .empty
        } catch {
            state = .failed(CineFlowError.from(error, fallbackCategory: .database).userMessage)
        }
    }

    public func cardModel(for entry: WatchHistoryItem) -> CFMediaCardModel {
        CFMediaCardModel(
            id: entry.episodeID ?? entry.mediaID,
            title: title(for: entry),
            metadata: "\(Int(entry.progressPercent.rounded()))% · \(dateTitle(entry.lastWatchedAt))",
            badge: entry.completed ? "Completed" : nil,
            progress: entry.progressPercent / 100,
            accentIndex: abs((entry.episodeID ?? entry.mediaID).hashValue)
        )
    }

    private func title(for entry: WatchHistoryItem) -> String {
        if entry.mediaID.contains(":tv:") {
            return entry.episodeID == nil ? "Сериал" : "Серия"
        }
        return "Фильм"
    }

    private func dateTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
