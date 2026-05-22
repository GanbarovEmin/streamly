import XCTest
@testable import CineFlowLocalization

final class LocalizationTests: XCTestCase {
    func testRussianAndEnglishNavigationStringsResolve() {
        XCTAssertEqual(L10n.string(.navigationHome, language: .ru), "Главная")
        XCTAssertEqual(L10n.string(.navigationHome, language: .en), "Home")
        XCTAssertEqual(L10n.string(.navigationSettings, language: .ru), "Настройки")
        XCTAssertEqual(L10n.string(.navigationSettings, language: .en), "Settings")
    }

    func testLanguageOptionsAreReadyForSettingsPicker() {
        XCTAssertEqual(AppLanguage.allCases, [.system, .ru, .en])
        XCTAssertEqual(AppLanguage.ru.displayNameKey, .languageRussian)
        XCTAssertEqual(AppLanguage.en.displayNameKey, .languageEnglish)
    }

    @MainActor
    func testLanguageSelectionPersistsInUserDefaults() {
        let suiteName = "CineFlowLocalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = LanguageSettingsStore(userDefaults: defaults)
        XCTAssertEqual(store.selectedLanguage, .system)

        store.setLanguage(.en)

        let reloadedStore = LanguageSettingsStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.selectedLanguage, .en)
    }

    func testFormattedStringsUseSelectedLocalizationBundle() {
        XCTAssertEqual(L10n.format(.bestReleaseFormat, language: .en, "Matrix 4K", 88), "Matrix 4K · 88 seeders")
        XCTAssertEqual(L10n.format(.bestReleaseFormat, language: .ru, "Matrix 4K", 88), "Matrix 4K · 88 сидов")
    }

    func testReleaseResourceBundleResolverUsesStreamlyBundleName() throws {
        XCTAssertEqual(L10n.releaseResourceBundleNames.first, "Streamly_CineFlowLocalization.bundle")

        let resourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StreamlyLocalizationReleaseBundleTests-\(UUID().uuidString)", isDirectory: true)
        let bundleURL = resourceURL.appendingPathComponent("Streamly_CineFlowLocalization.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.streamly.localization-test</string>
            <key>CFBundleName</key>
            <string>Streamly_CineFlowLocalization</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
        </dict>
        </plist>
        """.write(to: bundleURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: resourceURL) }

        XCTAssertNotNil(L10n.releaseResourceBundle(in: resourceURL))
    }

    func testUXWritingKeysResolveInRussianAndEnglish() {
        let keys: [L10nKey] = [
            .commonRetry,
            .searchStateIdleAction,
            .searchStateErrorMessage,
            .searchStateErrorRecovery,
            .detailEmptyAction,
            .detailErrorMessage,
            .detailErrorRecovery,
            .seriesStateEmptyAction,
            .seriesStateErrorMessage,
            .seriesStateErrorRecovery,
            .homeEmptyAction,
            .homeErrorMessage,
            .homeErrorRecovery,
            .libraryErrorMessage,
            .libraryEmptyAllTitle,
            .libraryEmptyAllMessage,
            .libraryEmptyActionSearch,
            .listsErrorMessage,
            .listsEmptyAction,
            .continueErrorMessage,
            .continueEmptyAction,
            .historyErrorMessage,
            .historyFilterEmptyAction,
            .sourcesHeaderTitle,
            .sourcesErrorMessage,
            .sourcesErrorRecovery,
            .sourcesAuthAuthenticated,
            .sourcesAuthInvalid,
            .sourcesAuthNotRequired,
            .sourcesAuthRequired,
            .sourcesHealthHealthy,
            .sourcesHealthDisabled,
            .sourcesHealthNeedsAuthentication,
            .sourcesHealthDegraded,
            .sourcesHealthUnavailable,
            .sourcesStatusSuccessRateFormat,
            .releaseHealthExcellent,
            .releaseHealthGood,
            .releaseHealthWeak,
            .releaseHealthNoSeeders,
            .releaseHealthUnknown,
            .releaseExplanationAdvanced,
            .releaseExplanationTooltipTitle,
            .releaseExplanationTooltipScoreFormat,
            .releaseExplanationLabelBest,
            .releaseExplanationLabelFastest,
            .releaseExplanationLabelSmallest,
            .releaseExplanationLabelBestRussianAudio,
            .releaseExplanationLabelBest4K,
            .releaseExplanationReasonBestOverall,
            .releaseExplanationReasonHighestSeeders,
            .releaseExplanationReasonSmallestFile,
            .releaseExplanationReason4K,
            .releaseExplanationReason1080p,
            .releaseExplanationReason720p,
            .releaseExplanationReasonHDR,
            .releaseExplanationReasonHEVC,
            .releaseExplanationReasonRussianAudio,
            .releaseExplanationReasonEnglishSubtitles,
            .releaseExplanationReasonTrustedSource,
            .releaseExplanationReasonHealthy,
            .releaseExplanationReasonFitsSize,
            .releaseExplanationReasonAudioFormat,
            .releaseExplanationReasonSubtitlesFormat,
            .releaseExplanationAdvancedScoreFormat,
            .releaseExplanationAdvancedSourceFormat,
            .releaseExplanationAdvancedQualityFormat,
            .releaseExplanationAdvancedSeedersFormat,
            .releaseExplanationAdvancedSizeFormat,
            .releaseExplanationAdvancedHDRFormat,
            .releaseExplanationAdvancedCodecFormat,
            .releaseExplanationAdvancedAudioFormat,
            .releaseExplanationAdvancedSubtitlesFormat,
            .releaseExplanationAdvancedHealthFormat,
            .cacheErrorMessage,
            .settingsUpdateNotChecked,
            .settingsUpdateIdle,
            .settingsUpdateChecking,
            .settingsUpdateUpToDate,
            .settingsUpdateFailed,
            .playerTitleFallback,
            .playerControlRewind,
            .playerControlPlayPause,
            .playerControlForward,
            .playerControlMute,
            .playerControlVolume,
            .playerControlAudio,
            .playerControlSubtitles,
            .playerControlSubtitlesOff,
            .playerControlFindOnline,
            .playerControlLoadLocalFile,
            .playerControlSpeed,
            .playerControlPictureInPicture,
            .playerControlFullscreen,
            .playerControlBack,
            .playerControlExit,
            .playerResumeTitle,
            .playerResumeMessageFormat,
            .playerResumeContinue,
            .playerResumeStartOver,
            .playerNextEpisodeTitle,
            .playerNextEpisodeAction,
            .playerNextEpisodeDismiss,
            .playerBufferingTitle,
            .playerBufferingMessageFormat,
            .playerAdvancedDetails,
            .playerControlTimeline,
            .playerPlaybackErrorMessage,
            .playerUnsupportedSourceMessage,
            .playerTorrentErrorMessage,
            .playerFallbackTryNext,
            .playerFallbackFailedToStartTitle,
            .playerFallbackNoSeedersTitle,
            .playerFallbackStalledTitle,
            .playerFallbackUnsupportedTitle,
            .playerFallbackMissingMediaTitle,
            .playerFallbackAlternativeFormat,
            .playerFallbackNoAlternativeMessage,
            .playerFileSelectionTitle,
            .playerFileSelectionMessage,
            .tooltipRankingScore,
            .tooltipSeeders,
            .tooltipCache,
            .tooltipDiagnostics,
            .tooltipAutoUpdates,
            .accessibilityCardOpenDetails,
            .accessibilityCarouselHint,
            .accessibilityImageLoading,
            .accessibilityImageUnavailable
        ]

        for language in [AppLanguage.ru, .en] {
            for key in keys {
                let value = L10n.string(key, language: language)
                XCTAssertFalse(value.isEmpty, "\(key.rawValue) is empty for \(language.rawValue)")
                XCTAssertNotEqual(value, key.rawValue, "\(key.rawValue) is missing for \(language.rawValue)")
            }
        }

        XCTAssertEqual(L10n.format(.settingsUpdateAvailableFormat, language: .en, "2.0.0"), "Version 2.0.0 available")
        XCTAssertEqual(L10n.format(.settingsUpdateAvailableFormat, language: .ru, "2.0.0"), "Доступна версия 2.0.0")
        XCTAssertEqual(L10n.format(.playerBufferingFormat, language: .en, 42), "Buffering 42%")
        XCTAssertEqual(L10n.format(.playerBufferingFormat, language: .ru, 42), "Буферизация 42%")
    }
}
