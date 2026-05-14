import CineFlowCore
import Foundation

public struct PersonRoutePayload: Hashable, Sendable {
    public let id: String
    public let name: String
    public let role: String?
    public let profileURL: URL?
    public let sourceMedia: PersonSourceMedia?

    public init(
        id: String,
        name: String,
        role: String? = nil,
        profileURL: URL? = nil,
        sourceMedia: PersonSourceMedia? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.profileURL = profileURL
        self.sourceMedia = sourceMedia
    }
}

public struct PersonSourceMedia: Hashable, Sendable {
    public let id: String
    public let title: String
    public let kind: MediaKind
    public let year: Int?
    public let posterURL: URL?
    public let backdropURL: URL?

    public init(
        id: String,
        title: String,
        kind: MediaKind,
        year: Int?,
        posterURL: URL? = nil,
        backdropURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.year = year
        self.posterURL = posterURL
        self.backdropURL = backdropURL
    }

    public init(mediaItem: MediaItem) {
        self.init(
            id: mediaItem.id,
            title: mediaItem.displayTitle,
            kind: mediaItem.kind,
            year: mediaItem.metadata?.year ?? mediaItem.releaseYear,
            posterURL: mediaItem.bestPosterURL,
            backdropURL: mediaItem.bestBackdropURL
        )
    }

    public var mediaItem: MediaItem {
        MediaItem(
            id: id,
            title: title,
            kind: kind,
            overview: "",
            releaseYear: year,
            posterPath: posterURL?.absoluteString,
            metadata: MediaMetadata(
                tmdbId: Int(id.split(separator: ":").last ?? "0") ?? 0,
                title: title,
                originalTitle: title,
                overview: "",
                year: year,
                posterURL: posterURL,
                backdropURL: backdropURL
            )
        )
    }
}

public enum PersonKind: String, Equatable, Sendable {
    case actor
    case director
}

public enum PersonDetailState: Equatable, Sendable {
    case loading
    case loaded
    case empty
    case failed(String)
}

public enum PersonFilmographySort: String, CaseIterable, Identifiable, Equatable, Sendable {
    case popularity
    case year
    case rating

    public var id: String { rawValue }
}

public enum PersonAvailabilityFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case available

    public var id: String { rawValue }
}

public struct PersonDetail: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: PersonKind
    public let role: String?
    public let photoURL: URL?
    public let shortBio: String
    public let knownFor: [MediaItem]

    public init(
        id: String,
        name: String,
        kind: PersonKind,
        role: String? = nil,
        photoURL: URL? = nil,
        shortBio: String,
        knownFor: [MediaItem] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.role = role
        self.photoURL = photoURL
        self.shortBio = shortBio
        self.knownFor = knownFor
    }
}

public struct PersonFilmographyCredit: Identifiable, Equatable, Sendable {
    public let mediaItem: MediaItem
    public let role: String
    public let popularityScore: Double
    public let isAvailableInSources: Bool
    public let isAvailableInLibrary: Bool

    public var id: String { mediaItem.id }

    public init(
        mediaItem: MediaItem,
        role: String,
        popularityScore: Double,
        isAvailableInSources: Bool = false,
        isAvailableInLibrary: Bool = false
    ) {
        self.mediaItem = mediaItem
        self.role = role
        self.popularityScore = popularityScore
        self.isAvailableInSources = isAvailableInSources
        self.isAvailableInLibrary = isAvailableInLibrary
    }

    public var isAvailable: Bool {
        isAvailableInSources || isAvailableInLibrary
    }

    public var rating: Double {
        mediaItem.metadata?.rating ?? 0
    }

    public var year: Int {
        mediaItem.metadata?.year ?? mediaItem.releaseYear ?? 0
    }

    public func withLibraryAvailability(_ isAvailableInLibrary: Bool) -> PersonFilmographyCredit {
        PersonFilmographyCredit(
            mediaItem: mediaItem,
            role: role,
            popularityScore: popularityScore,
            isAvailableInSources: isAvailableInSources,
            isAvailableInLibrary: isAvailableInLibrary
        )
    }
}

public struct PersonDetailResponse: Equatable, Sendable {
    public let detail: PersonDetail
    public let filmography: [PersonFilmographyCredit]

    public init(detail: PersonDetail, filmography: [PersonFilmographyCredit]) {
        self.detail = detail
        self.filmography = filmography
    }
}

public protocol PersonDetailProviderProtocol: Sendable {
    func personDetail(for person: PersonRoutePayload) async throws -> PersonDetailResponse?
}

public struct MockPersonDetailProvider: PersonDetailProviderProtocol {
    public init() {}

    public func personDetail(for person: PersonRoutePayload) async throws -> PersonDetailResponse? {
        guard person.id == "keanu" else { return nil }
        let matrix = Self.media(
            id: "tmdb:movie:603",
            title: "The Matrix",
            year: 1999,
            rating: 8.7,
            releases: [
                TorrentRelease(
                    id: "matrix-available",
                    sourceName: "Torrentio",
                    title: "The Matrix 2160p",
                    quality: .ultraHD,
                    seeders: 80
                )
            ]
        )
        let johnWick = Self.media(id: "tmdb:movie:245891", title: "John Wick", year: 2014, rating: 7.4)
        let matrixResurrections = Self.media(id: "tmdb:movie:624860", title: "The Matrix Resurrections", year: 2021, rating: 5.7)

        return PersonDetailResponse(
            detail: PersonDetail(
                id: person.id,
                name: "Keanu Reeves",
                kind: .actor,
                role: person.role,
                photoURL: person.profileURL,
                shortBio: "Known for focused action roles and modern science-fiction classics.",
                knownFor: [matrix, johnWick]
            ),
            filmography: [
                PersonFilmographyCredit(mediaItem: matrix, role: "Neo", popularityScore: 100, isAvailableInSources: true),
                PersonFilmographyCredit(mediaItem: johnWick, role: "John Wick", popularityScore: 92),
                PersonFilmographyCredit(mediaItem: matrixResurrections, role: "Neo", popularityScore: 56)
            ]
        )
    }

    private static func media(
        id: String,
        title: String,
        year: Int,
        rating: Double,
        releases: [TorrentRelease] = []
    ) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            kind: .movie,
            overview: "\(title) overview",
            releaseYear: year,
            posterPath: nil,
            metadata: MediaMetadata(
                tmdbId: Int(id.split(separator: ":").last ?? "0") ?? 0,
                title: title,
                originalTitle: title,
                overview: "\(title) overview",
                year: year,
                rating: rating
            ),
            torrentReleases: releases
        )
    }
}

@MainActor
public final class PersonDetailViewModel: ObservableObject {
    @Published public private(set) var state: PersonDetailState = .loading
    @Published public private(set) var detail: PersonDetail?
    @Published public private(set) var filmography: [PersonFilmographyCredit] = []
    @Published public var sort: PersonFilmographySort = .popularity
    @Published public var availabilityFilter: PersonAvailabilityFilter = .all

    private let person: PersonRoutePayload
    private let provider: any PersonDetailProviderProtocol
    private let libraryRepository: (any LibraryRepositoryProtocol)?

    public init(
        person: PersonRoutePayload,
        provider: any PersonDetailProviderProtocol,
        libraryRepository: (any LibraryRepositoryProtocol)? = nil
    ) {
        self.person = person
        self.provider = provider
        self.libraryRepository = libraryRepository
    }

    public var knownFor: [MediaItem] {
        if let knownFor = detail?.knownFor, !knownFor.isEmpty {
            return knownFor
        }
        return Array(filmography.prefix(4).map(\.mediaItem))
    }

    public var visibleFilmography: [PersonFilmographyCredit] {
        let filtered = availabilityFilter == .available ? filmography.filter(\.isAvailable) : filmography
        switch sort {
        case .popularity:
            return filtered.sorted { lhs, rhs in
                if lhs.popularityScore == rhs.popularityScore { return lhs.mediaItem.displayTitle < rhs.mediaItem.displayTitle }
                return lhs.popularityScore > rhs.popularityScore
            }
        case .year:
            return filtered.sorted { lhs, rhs in
                if lhs.year == rhs.year { return lhs.mediaItem.displayTitle < rhs.mediaItem.displayTitle }
                return lhs.year > rhs.year
            }
        case .rating:
            return filtered.sorted { lhs, rhs in
                if lhs.rating == rhs.rating { return lhs.mediaItem.displayTitle < rhs.mediaItem.displayTitle }
                return lhs.rating > rhs.rating
            }
        }
    }

    public var photoFallbackInitials: String {
        Self.initials(for: detail?.name ?? person.name)
    }

    public var bioFallbackTitle: String? {
        guard detail?.shortBio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else { return nil }
        return "Биография пока не загружена"
    }

    public var filmographyFallbackTitle: String? {
        filmography.isEmpty ? "Фильмография пока недоступна" : nil
    }

    public func load() async {
        state = .loading
        do {
            guard let response = try await provider.personDetail(for: person) else {
                state = .empty
                return
            }
            detail = response.detail
            let libraryIDs = await loadedLibraryIDs()
            filmography = response.filmography.map { credit in
                credit.withLibraryAvailability(libraryIDs.contains(credit.mediaItem.id))
            }
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func addToWatchlist(_ item: MediaItem) async throws {
        guard let libraryRepository else { return }
        let list = try await libraryRepository.defaultList()
        try await libraryRepository.add(item, to: list.id)
    }

    private func loadedLibraryIDs() async -> Set<String> {
        guard let libraryRepository else { return [] }
        do {
            return Set(try await libraryRepository.items().map(\.id))
        } catch {
            return []
        }
    }

    private static func initials(for name: String) -> String {
        let initials = name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map { String($0).uppercased() }
            .joined()
        return initials.isEmpty ? "?" : initials
    }
}
