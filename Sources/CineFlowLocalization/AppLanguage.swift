import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case ru
    case en

    public static let storageKey = "cineflow.interfaceLanguage"

    public var id: String { rawValue }

    public var localeIdentifier: String? {
        switch self {
        case .system:
            nil
        case .ru:
            "ru"
        case .en:
            "en"
        }
    }

    public var displayNameKey: L10nKey {
        switch self {
        case .system:
            .languageSystem
        case .ru:
            .languageRussian
        case .en:
            .languageEnglish
        }
    }
}
