import Foundation

public enum L10n {
    public static func string(_ key: L10nKey, language: AppLanguage = .system) -> String {
        NSLocalizedString(key.rawValue, bundle: bundle(for: language), comment: "")
    }

    public static func format(_ key: L10nKey, language: AppLanguage = .system, _ arguments: CVarArg...) -> String {
        let template = string(key, language: language)
        let locale = Locale(identifier: language.localeIdentifier ?? Locale.current.identifier)
        return String(format: template, locale: locale, arguments: arguments)
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        let moduleBundle = releaseResourceBundle ?? Bundle.module
        guard
            let localeIdentifier = language.localeIdentifier,
            let path = moduleBundle.path(forResource: localeIdentifier, ofType: "lproj"),
            let localizedBundle = Bundle(path: path)
        else {
            return moduleBundle
        }

        return localizedBundle
    }

    static let releaseResourceBundleNames = [
        "Streamly_CineFlowLocalization.bundle",
        "CineFlowLocalization_CineFlowLocalization.bundle",
        "CineFlow_CineFlowLocalization.bundle"
    ]

    static func releaseResourceBundle(in resourceURL: URL?) -> Bundle? {
        guard let resourceURL else { return nil }
        for bundleName in releaseResourceBundleNames {
            if let bundle = Bundle(url: resourceURL.appendingPathComponent(bundleName, isDirectory: true)) {
                return bundle
            }
        }
        return nil
    }

    private static var releaseResourceBundle: Bundle? {
        releaseResourceBundle(in: Bundle.main.resourceURL)
    }
}
