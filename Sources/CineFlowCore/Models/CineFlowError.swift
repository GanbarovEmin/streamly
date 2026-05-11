import Foundation

public enum CineFlowErrorCategory: String, Codable, CaseIterable, Equatable, Sendable {
    case network
    case metadata
    case source
    case authentication
    case torrent
    case playback
    case subtitles
    case database
    case cache
    case update
    case permissions
    case unknown

    public var diagnosticsSubsystem: DiagnosticsSubsystem {
        switch self {
        case .metadata:
            .metadata
        case .source, .authentication:
            .source
        case .torrent:
            .torrent
        case .playback:
            .playback
        case .subtitles:
            .subtitle
        case .database:
            .database
        case .update:
            .update
        case .network, .cache, .permissions, .unknown:
            .app
        }
    }
}

public struct CineFlowError: LocalizedError, Equatable, Sendable {
    public let category: CineFlowErrorCategory
    public let technicalDescription: String
    public let userMessage: String
    public let recoverySuggestion: String
    public let logLevel: DiagnosticsLogLevel

    public init(
        category: CineFlowErrorCategory,
        technicalDescription: String,
        userMessage: String,
        recoverySuggestion: String,
        logLevel: DiagnosticsLogLevel
    ) {
        self.category = category
        self.technicalDescription = technicalDescription
        self.userMessage = userMessage
        self.recoverySuggestion = recoverySuggestion
        self.logLevel = logLevel
    }

    public var errorDescription: String? {
        userMessage
    }

    public var failureReason: String? {
        technicalDescription
    }

    public static func from(_ error: Error, fallbackCategory: CineFlowErrorCategory = .unknown) -> CineFlowError {
        if let cineFlowError = error as? CineFlowError {
            return cineFlowError
        }

        if let convertible = error as? CineFlowErrorConvertible {
            return convertible.cineFlowError
        }

        if let urlError = error as? URLError {
            return network(urlError)
        }

        if let cocoaError = error as? CocoaError {
            return cocoa(cocoaError, fallbackCategory: fallbackCategory)
        }

        return generic(error, category: fallbackCategory)
    }

    private static func network(_ error: URLError) -> CineFlowError {
        let suggestion: String
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost:
            suggestion = "Check your internet connection and try again."
        case .timedOut:
            suggestion = "Wait a moment and retry the request."
        default:
            suggestion = "Try again. If the problem continues, check the service status."
        }

        return CineFlowError(
            category: .network,
            technicalDescription: "URLError.\(urlErrorCodeName(error.code)) \(error.localizedDescription)",
            userMessage: "Streamly cannot reach the network right now.",
            recoverySuggestion: suggestion,
            logLevel: .warning
        )
    }

    private static func urlErrorCodeName(_ code: URLError.Code) -> String {
        switch code {
        case .notConnectedToInternet:
            "notConnectedToInternet"
        case .networkConnectionLost:
            "networkConnectionLost"
        case .cannotConnectToHost:
            "cannotConnectToHost"
        case .timedOut:
            "timedOut"
        case .badServerResponse:
            "badServerResponse"
        default:
            "\(code.rawValue)"
        }
    }

    private static func cocoa(_ error: CocoaError, fallbackCategory: CineFlowErrorCategory) -> CineFlowError {
        if error.code == .fileReadNoPermission || error.code == .fileWriteNoPermission {
            return CineFlowError(
                category: .permissions,
                technicalDescription: "CocoaError.\(error.code.rawValue) \(error.localizedDescription)",
                userMessage: "Streamly does not have permission to access this file.",
                recoverySuggestion: "Choose another file or grant access in macOS privacy settings.",
                logLevel: .warning
            )
        }

        return generic(error, category: fallbackCategory)
    }

    private static func generic(_ error: Error, category: CineFlowErrorCategory) -> CineFlowError {
        CineFlowError(
            category: category,
            technicalDescription: String(describing: error),
            userMessage: defaultUserMessage(for: category),
            recoverySuggestion: defaultRecoverySuggestion(for: category),
            logLevel: defaultLogLevel(for: category)
        )
    }

    public static func defaultUserMessage(for category: CineFlowErrorCategory) -> String {
        switch category {
        case .network:
            "Streamly cannot reach the network right now."
        case .metadata:
            "Metadata could not be loaded."
        case .source:
            "This source is temporarily unavailable."
        case .authentication:
            "Sign in is required for this source."
        case .torrent:
            "Torrent processing failed."
        case .playback:
            "Playback is not available right now."
        case .subtitles:
            "Subtitles could not be loaded."
        case .database:
            "Local library data could not be opened."
        case .cache:
            "Cache operation failed."
        case .update:
            "Update check failed."
        case .permissions:
            "Streamly does not have permission to complete this action."
        case .unknown:
            "Something went wrong."
        }
    }

    public static func defaultRecoverySuggestion(for category: CineFlowErrorCategory) -> String {
        switch category {
        case .network:
            "Check your internet connection and try again."
        case .authentication:
            "Open source settings and sign in again."
        case .permissions:
            "Review macOS permissions and retry."
        case .playback:
            "Try another release or restart playback."
        case .torrent:
            "Try another release or source."
        case .database:
            "Restart Streamly. If the problem continues, export diagnostics."
        case .update:
            "Try again later or download the latest build manually."
        default:
            "Try again. If the problem continues, export diagnostics."
        }
    }

    public static func defaultLogLevel(for category: CineFlowErrorCategory) -> DiagnosticsLogLevel {
        switch category {
        case .network, .source, .authentication, .permissions, .subtitles, .update:
            .warning
        case .metadata, .torrent, .playback, .database, .cache:
            .error
        case .unknown:
            .error
        }
    }
}

public protocol CineFlowErrorConvertible {
    var cineFlowError: CineFlowError { get }
}

public extension DiagnosticsServiceProtocol {
    func log(_ error: CineFlowError, operation: String, metadata: [String: String] = [:]) async {
        var payload = metadata
        payload["operation"] = operation
        payload["category"] = error.category.rawValue
        payload["technicalDescription"] = error.technicalDescription
        await log(
            level: error.logLevel,
            subsystem: error.category.diagnosticsSubsystem,
            message: error.userMessage,
            metadata: payload
        )
    }
}

extension TorrentEngineError: CineFlowErrorConvertible {
    public var cineFlowError: CineFlowError {
        CineFlowError(
            category: .torrent,
            technicalDescription: errorDescription ?? String(describing: self),
            userMessage: CineFlowError.defaultUserMessage(for: .torrent),
            recoverySuggestion: CineFlowError.defaultRecoverySuggestion(for: .torrent),
            logLevel: .error
        )
    }
}

extension PlaybackServiceError: CineFlowErrorConvertible {
    public var cineFlowError: CineFlowError {
        CineFlowError(
            category: .playback,
            technicalDescription: errorDescription ?? String(describing: self),
            userMessage: CineFlowError.defaultUserMessage(for: .playback),
            recoverySuggestion: CineFlowError.defaultRecoverySuggestion(for: .playback),
            logLevel: .error
        )
    }
}

extension SubtitleServiceError: CineFlowErrorConvertible {
    public var cineFlowError: CineFlowError {
        CineFlowError(
            category: .subtitles,
            technicalDescription: errorDescription ?? String(describing: self),
            userMessage: CineFlowError.defaultUserMessage(for: .subtitles),
            recoverySuggestion: CineFlowError.defaultRecoverySuggestion(for: .subtitles),
            logLevel: .warning
        )
    }
}

extension SourceProviderError: CineFlowErrorConvertible {
    public var cineFlowError: CineFlowError {
        switch self {
        case .authenticationUnsupported, .authenticationRequired:
            CineFlowError(
                category: .authentication,
                technicalDescription: errorDescription ?? String(describing: self),
                userMessage: "Sign in again for this source.",
                recoverySuggestion: "Open Source settings and refresh the source session.",
                logLevel: .warning
            )
        case .timedOut:
            CineFlowError(
                category: .source,
                technicalDescription: errorDescription ?? String(describing: self),
                userMessage: "This source took too long to respond.",
                recoverySuggestion: "Retry the search or temporarily disable this source.",
                logLevel: .warning
            )
        case .providerUnavailable:
            CineFlowError(
                category: .source,
                technicalDescription: errorDescription ?? String(describing: self),
                userMessage: "This source is temporarily unavailable.",
                recoverySuggestion: "Retry later or disable this source in Settings.",
                logLevel: .warning
            )
        case .releaseNotFound:
            CineFlowError(
                category: .source,
                technicalDescription: errorDescription ?? String(describing: self),
                userMessage: "This release is no longer available from the source.",
                recoverySuggestion: "Choose another release or refresh sources.",
                logLevel: .warning
            )
        }
    }
}
