import CineFlowCore
import CineFlowDesignSystem
import CineFlowLocalization
import CineFlowSources
import AppKit
import SwiftUI

public struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @State private var selection: SettingsSectionID = .general
    @State private var sourceUsername: [String: String] = [:]
    @State private var sourcePassword: [String: String] = [:]
    @State private var sourceCookies: [String: String] = [:]
    @State private var tmdbReadAccessToken = ""
    @State private var tmdbAPIKey = ""
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    public init(viewModel: SettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(CFColors.separator)
            detail
        }
        .task { await viewModel.load() }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(viewModel.sections) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section.id)
            }
        }
        .listStyle(.sidebar)
        .frame(width: 240)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CFSpacing.lg) {
                header

                switch selection {
                case .general: generalSection
                case .appearance: appearanceSection
                case .home: homeSection
                case .tasteProfile: tasteProfileSection
                case .sources: sourcesSection
                case .playback: playbackSection
                case .subtitles: subtitlesSection
                case .cache: cacheSection
                case .updates: updatesSection
                case .diagnostics: diagnosticsSection
                case .privacy: privacySection
                case .about: aboutSection
                }

                if let message = viewModel.operationMessage {
                    Text(message)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                }
            }
            .padding(CFSpacing.xl)
            .frame(maxWidth: 880, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: CFSpacing.xs) {
            Text(selection.title)
                .font(CFTypography.largeTitle)
                .foregroundStyle(CFColors.textPrimary)

            Text(sectionDescription(selection))
                .font(CFTypography.body)
                .foregroundStyle(CFColors.textSecondary)
        }
    }

    private var generalSection: some View {
        SettingsCard {
            Picker("Language", selection: Binding(
                get: { viewModel.settings.general.language },
                set: { value in Task { await viewModel.updateLanguage(value) } }
            )) {
                Text("System").tag(AppLanguageSetting.system)
                Text("Russian").tag(AppLanguageSetting.russian)
                Text("English").tag(AppLanguageSetting.english)
            }
            .pickerStyle(.segmented)

            SettingsToggleRow(title: "Launch at login", subtitle: "Optional startup behavior for the macOS app.", isOn: Binding(
                get: { viewModel.settings.general.launchAtLogin },
                set: { value in Task { await viewModel.updateLaunchAtLogin(value) } }
            ))

            SettingsToggleRow(title: "Open last screen on launch", subtitle: "Restore the last active Streamly area after restart.", isOn: Binding(
                get: { viewModel.settings.general.openLastScreenOnLaunch },
                set: { value in Task { await viewModel.updateOpenLastScreenOnLaunch(value) } }
            ))
        }
    }

    private var appearanceSection: some View {
        SettingsCard {
            SettingsToggleRow(title: "Dark Mode only", subtitle: "Streamly is locked to the dark design system.", isOn: .constant(viewModel.settings.appearance.darkModeOnly))
                .disabled(true)

            SettingValueRow(title: "Accent color", value: "Neon purple locked")

            SettingsToggleRow(title: "Reduce motion", subtitle: "Use calmer transitions where motion is optional.", isOn: Binding(
                get: { viewModel.settings.appearance.reduceMotion },
                set: { value in Task { await viewModel.updateReduceMotion(value) } }
            ))
        }
    }

    private var homeSection: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: CFSpacing.md) {
                Text("Start page layout")
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)

                Picker("Layout density", selection: Binding(
                    get: { viewModel.settings.home.layoutDensity },
                    set: { value in Task { await viewModel.updateHomeLayoutDensity(value) } }
                )) {
                    Text("Compact").tag(HomeLayoutDensity.compact)
                    Text("Comfortable").tag(HomeLayoutDensity.comfortable)
                }
                .pickerStyle(.segmented)

                Picker("Poster size", selection: Binding(
                    get: { viewModel.settings.home.posterSize },
                    set: { value in Task { await viewModel.updateHomePosterSize(value) } }
                )) {
                    Text("Small").tag(HomePosterSizePreference.small)
                    Text("Medium").tag(HomePosterSizePreference.medium)
                    Text("Large").tag(HomePosterSizePreference.large)
                }
                .pickerStyle(.segmented)

                SettingsToggleRow(title: "Local recommendations", subtitle: "Use watched genres, favorites, ratings and local progress without cloud analytics.", isOn: Binding(
                    get: { viewModel.settings.recommendations.localRecommendationsEnabled },
                    set: { value in Task { await viewModel.updateLocalRecommendationsEnabled(value) } }
                ))
            }

            Divider().overlay(CFColors.separatorSubtle)

            VStack(alignment: .leading, spacing: CFSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Visible sections")
                            .font(CFTypography.bodyEmphasis)
                            .foregroundStyle(CFColors.textPrimary)
                        Text("Rows stay local-first and can be synced later with the stored section IDs.")
                            .font(CFTypography.caption)
                            .foregroundStyle(CFColors.textMuted)
                    }
                    Spacer()
                    SecondaryButton("Reset to defaults", systemImage: "arrow.counterclockwise") {
                        Task { await viewModel.resetHomePreferences() }
                    }
                }

                let orderedSections = viewModel.settings.home.orderedSections
                ForEach(Array(orderedSections.enumerated()), id: \.element.sectionID) { index, preference in
                    HStack(alignment: .center, spacing: CFSpacing.md) {
                        Toggle(isOn: Binding(
                            get: { preference.isEnabled },
                            set: { value in Task { await viewModel.updateHomeSection(preference.sectionID, isEnabled: value) } }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(homeSectionTitle(preference.sectionID))
                                    .font(CFTypography.body)
                                    .foregroundStyle(CFColors.textPrimary)
                                Text(preference.sectionID)
                                    .font(CFTypography.caption)
                                    .foregroundStyle(CFColors.textMuted)
                            }
                        }
                        .toggleStyle(.switch)

                        Spacer(minLength: CFSpacing.md)

                        HStack(spacing: CFSpacing.xs) {
                            Button {
                                Task { await viewModel.moveHomeSection(preference.sectionID, direction: .up) }
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .accessibilityLabel("Move \(homeSectionTitle(preference.sectionID)) up")

                            Button {
                                Task { await viewModel.moveHomeSection(preference.sectionID, direction: .down) }
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == orderedSections.count - 1)
                            .accessibilityLabel("Move \(homeSectionTitle(preference.sectionID)) down")
                        }
                    }
                    .settingsDivider(unlessLast: index != orderedSections.count - 1)
                }
            }
        }
    }

    private var sourcesSection: some View {
        SettingsCard {
            tmdbMetadataCredentials
            Divider().overlay(CFColors.separatorSubtle)
            torrentioConfiguration
            Divider().overlay(CFColors.separatorSubtle)

            if viewModel.sourceRows.isEmpty {
                EmptyState(
                    title: t(.sourcesEmptyTitle),
                    message: t(.sourcesEmptyMessage),
                    systemImage: "externaldrive",
                    actionTitle: t(.sourcesEmptyAction),
                    actionSystemImage: "arrow.counterclockwise"
                ) {
                    Task { await viewModel.resetTorrentioSettings() }
                }
            } else {
                ForEach(viewModel.sourceRows) { row in
                    VStack(alignment: .leading, spacing: CFSpacing.sm) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.displayName)
                                    .font(CFTypography.bodyEmphasis)
                                    .foregroundStyle(CFColors.textPrimary)
                                Text(row.statusText)
                                    .font(CFTypography.caption)
                                    .foregroundStyle(CFColors.textMuted)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { row.settings.isEnabled },
                                set: { value in Task { await viewModel.setSourceEnabled(value, sourceID: row.id) } }
                            ))
                            .labelsHidden()
                        }

                        if row.requiresAuthentication {
                            HStack(spacing: CFSpacing.sm) {
                                TextField("Login", text: binding($sourceUsername, row.id))
                                SecureField("Password", text: binding($sourcePassword, row.id))
                                TextField("Cookies", text: binding($sourceCookies, row.id))
                            }
                            HStack(spacing: CFSpacing.sm) {
                                SecondaryButton("Save credentials", systemImage: "key") {
                                    Task {
                                        await viewModel.authenticateSource(
                                            sourceID: row.id,
                                            username: sourceUsername[row.id],
                                            password: sourcePassword[row.id],
                                            cookies: sourceCookies[row.id] ?? ""
                                        )
                                        sourcePassword[row.id] = ""
                                    }
                                }
                                SecondaryButton("Test connection", systemImage: "network") {
                                    Task { await viewModel.testConnection(sourceID: row.id) }
                                }
                                SecondaryButton("Clear session", systemImage: "xmark.circle") {
                                    Task { await viewModel.clearSourceSession(sourceID: row.id) }
                                }
                            }
                        } else {
                            SecondaryButton("Test connection", systemImage: "network") {
                                Task { await viewModel.testConnection(sourceID: row.id) }
                            }
                        }
                    }
                    .settingsDivider(unlessLast: row.id != viewModel.sourceRows.last?.id)
                }
            }
        }
    }

    private var tasteProfileSection: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: CFSpacing.md) {
                Text("Genre controls")
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                Text("These preferences stay local and adjust recommendations without cloud analytics.")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)

                ForEach(tasteGenreRows, id: \.self) { genre in
                    HStack(spacing: CFSpacing.md) {
                        Text(genre)
                            .font(CFTypography.body)
                            .foregroundStyle(CFColors.textPrimary)
                            .frame(width: 140, alignment: .leading)

                        Picker(genre, selection: Binding(
                            get: { viewModel.settings.tasteProfile.preference(forGenre: genre) },
                            set: { value in Task { await viewModel.updateTasteGenre(genre, preference: value) } }
                        )) {
                            Text("Neutral").tag(TastePreferenceLevel?.none)
                            Text("More").tag(TastePreferenceLevel?.some(.more))
                            Text("Less").tag(TastePreferenceLevel?.some(.less))
                            Text("Hide").tag(TastePreferenceLevel?.some(.hidden))
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                }
            }

            Divider().overlay(CFColors.separatorSubtle)

            VStack(alignment: .leading, spacing: CFSpacing.sm) {
                Text("Current profile")
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)

                if viewModel.settings.tasteProfile.genrePreferences.isEmpty {
                    Text("No manual genre overrides yet.")
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                } else {
                    ForEach(viewModel.settings.tasteProfile.genrePreferences) { preference in
                        SettingValueRow(title: preference.genre, value: preference.preference.rawValue.capitalized)
                    }
                }
            }

            Divider().overlay(CFColors.separatorSubtle)

            VStack(alignment: .leading, spacing: CFSpacing.sm) {
                Text("Hidden items")
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                Text("Hidden titles stay in Library and history, but are removed from recommendation rows.")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)

                if viewModel.hiddenRecommendationItems.isEmpty {
                    Text("No hidden recommendation items.")
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                } else {
                    ForEach(viewModel.hiddenRecommendationItems) { item in
                        HStack(spacing: CFSpacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(CFTypography.body)
                                    .foregroundStyle(CFColors.textPrimary)
                                Text(hiddenItemDetail(item))
                                    .font(CFTypography.caption)
                                    .foregroundStyle(CFColors.textMuted)
                            }
                            Spacer()
                            SecondaryButton("Restore", systemImage: "arrow.uturn.backward") {
                                Task { await viewModel.restoreHiddenRecommendationItem(mediaID: item.mediaID) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var torrentioConfiguration: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Torrentio")
                        .font(CFTypography.bodyEmphasis)
                        .foregroundStyle(CFColors.textPrimary)
                    Text("Configure the Stremio stream addon inside Streamly. Enable the source below when you want it used for movie releases.")
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                }
                Spacer()
                SecondaryButton("Reset", systemImage: "arrow.counterclockwise") {
                    Task { await viewModel.resetTorrentioSettings() }
                }
            }

            VStack(alignment: .leading, spacing: CFSpacing.sm) {
                Text("Providers")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
                HStack(spacing: CFSpacing.sm) {
                    ForEach(TorrentioProviderOption.allCases) { provider in
                        Toggle(provider.displayName, isOn: Binding(
                            get: { viewModel.torrentioSettings.providers.contains(provider) },
                            set: { value in Task { await viewModel.updateTorrentioProvider(provider, isSelected: value) } }
                        ))
                    }
                }
            }

            Picker("Priority language", selection: Binding(
                get: { viewModel.torrentioSettings.priorityLanguage },
                set: { value in Task { await viewModel.updateTorrentioPriorityLanguage(value) } }
            )) {
                ForEach(TorrentioPriorityLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: CFSpacing.sm) {
                Text("Excluded qualities")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: CFSpacing.sm)], alignment: .leading, spacing: CFSpacing.sm) {
                    ForEach(TorrentioExcludedQuality.allCases) { quality in
                        Toggle(quality.displayName, isOn: Binding(
                            get: { viewModel.torrentioSettings.excludedQualities.contains(quality) },
                            set: { value in Task { await viewModel.updateTorrentioExcludedQuality(quality, isExcluded: value) } }
                        ))
                    }
                }
            }

            Stepper(
                "Max results: \(viewModel.torrentioSettings.resultLimit ?? 10)",
                value: Binding(
                    get: { viewModel.torrentioSettings.resultLimit ?? 10 },
                    set: { value in Task { await viewModel.updateTorrentioResultLimit(value) } }
                ),
                in: 1...50
            )

            HStack(alignment: .center, spacing: CFSpacing.sm) {
                Text(viewModel.torrentioConfiguredManifestURL == nil ? "Манифест источника недоступен" : "Манифест источника собран и готов для копирования")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                SecondaryButton("Copy manifest", systemImage: "doc.on.doc") {
                    copyToPasteboard(viewModel.torrentioConfiguredManifestURL?.absoluteString)
                }
            }
        }
    }

    private var tmdbMetadataCredentials: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TMDB metadata")
                        .font(CFTypography.bodyEmphasis)
                        .foregroundStyle(CFColors.textPrimary)
                    Text(viewModel.tmdbCredentialSummary.statusText)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                    Text(viewModel.tmdbCredentialSummary.detailText)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                }
                Spacer()
                Image(systemName: viewModel.tmdbCredentialSummary.hasReadAccessToken || viewModel.tmdbCredentialSummary.hasAPIKey ? "checkmark.seal.fill" : "key.slash")
                    .foregroundStyle(viewModel.tmdbCredentialSummary.hasReadAccessToken || viewModel.tmdbCredentialSummary.hasAPIKey ? CFColors.success : CFColors.warning)
                    .font(.title3)
            }

            HStack(spacing: CFSpacing.sm) {
                SecureField("TMDB Read Access Token", text: $tmdbReadAccessToken)
                    .textFieldStyle(.roundedBorder)
                SecureField("TMDB API key", text: $tmdbAPIKey)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: CFSpacing.sm) {
                PrimaryButton("Save TMDB", systemImage: "key") {
                    Task {
                        await viewModel.saveTMDBCredentials(readAccessToken: tmdbReadAccessToken, apiKey: tmdbAPIKey)
                        tmdbReadAccessToken = ""
                        tmdbAPIKey = ""
                    }
                }
                SecondaryButton("Test TMDB", systemImage: "network") {
                    Task { await viewModel.validateTMDBCredentials() }
                }
                SecondaryButton("Clear TMDB", systemImage: "xmark.circle") {
                    Task {
                        await viewModel.clearTMDBCredentials()
                        tmdbReadAccessToken = ""
                        tmdbAPIKey = ""
                    }
                }
            }
        }
    }

    private var playbackSection: some View {
        SettingsCard {
            Picker("Preferred audio", selection: Binding(
                get: { viewModel.settings.playback.preferredAudioOrder },
                set: { value in Task { await viewModel.updatePreferredAudioOrder(value) } }
            )) {
                ForEach(PreferredAudioOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }

            Picker("Custom audio order", selection: Binding(
                get: { viewModel.settings.playback.preferredAudioLanguages.joined(separator: ",") },
                set: { value in Task { await viewModel.updatePreferredAudioLanguages(value.split(separator: ",").map(String.init)) } }
            )) {
                Text("Russian -> English").tag("ru,en")
                Text("English -> Russian").tag("en,ru")
                Text("English only").tag("en")
            }
            .disabled(viewModel.settings.playback.preferredAudioOrder != .custom)

            Picker("Preferred quality", selection: Binding(
                get: { viewModel.settings.playback.preferredQuality },
                set: { value in Task { await viewModel.updatePreferredQuality(value) } }
            )) {
                ForEach(PreferredQuality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }

            Picker("HDR preference", selection: Binding(
                get: { viewModel.settings.playback.hdrPreference },
                set: { value in Task { await viewModel.updateHDRPreference(value) } }
            )) {
                ForEach(HDRPreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            }

            Picker("Codec preference", selection: Binding(
                get: { viewModel.settings.playback.codecPreference },
                set: { value in Task { await viewModel.updateCodecPreference(value) } }
            )) {
                ForEach(CodecPreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            }

            Stepper(maxFileSizeStepperTitle, value: maxFileSizeGBBinding, in: 0...100, step: 1)

            SettingsToggleRow(title: "Prefer high seeders", subtitle: "Choose a healthier release over the absolute highest quality when the network looks stronger.", isOn: Binding(
                get: { viewModel.settings.playback.preferHighSeedersOverHighestQuality },
                set: { value in Task { await viewModel.updatePreferHighSeedersOverHighestQuality(value) } }
            ))

            SettingsToggleRow(title: "Hardware acceleration", subtitle: "Prefer GPU decoding when the playback backend supports it.", isOn: Binding(
                get: { viewModel.settings.playback.hardwareAccelerationEnabled },
                set: { value in Task { await viewModel.updateHardwareAcceleration(value) } }
            ))
            SettingsToggleRow(title: "Start from last position", subtitle: "Resume movies and episodes from saved progress.", isOn: Binding(
                get: { viewModel.settings.playback.startFromLastPosition },
                set: { value in Task { await viewModel.updateStartFromLastPosition(value) } }
            ))
            SettingsToggleRow(title: "Default fullscreen", subtitle: "Open playback in fullscreen by default.", isOn: Binding(
                get: { viewModel.settings.playback.defaultFullscreen },
                set: { value in Task { await viewModel.updateDefaultFullscreen(value) } }
            ))

            SettingsToggleRow(title: "Dim around video", subtitle: "Use a darker viewing surface around the player controls.", isOn: Binding(
                get: { viewModel.settings.playback.dimBackgroundAroundVideo },
                set: { value in Task { await viewModel.updateDimBackgroundAroundVideo(value) } }
            ))

            SettingsToggleRow(title: "Timeline previews", subtitle: "Show cached frame thumbnails while hovering the timeline.", isOn: Binding(
                get: { viewModel.settings.playback.enableTimelinePreviews },
                set: { value in Task { await viewModel.updateTimelinePreviewsEnabled(value) } }
            ))

            SettingsToggleRow(title: "Autoplay next episode", subtitle: "Start the next episode countdown at the end of a series episode.", isOn: Binding(
                get: { viewModel.settings.playback.autoplayNextEpisode },
                set: { value in Task { await viewModel.updateAutoplayNextEpisode(value) } }
            ))

            Slider(
                value: Binding(
                    get: { viewModel.settings.playback.rememberedVolume },
                    set: { value in Task { await viewModel.updateRememberedVolume(value) } }
                ),
                in: 0...1
            ) {
                Text("Default volume")
            } minimumValueLabel: {
                Image(systemName: "speaker.slash")
            } maximumValueLabel: {
                Image(systemName: "speaker.wave.3")
            }
            .accessibilityValue("\(Int(viewModel.settings.playback.rememberedVolume * 100))%")

            Picker("Default speed", selection: Binding(
                get: { viewModel.settings.playback.playbackSpeed },
                set: { value in Task { await viewModel.updateDefaultPlaybackSpeed(value) } }
            )) {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    Text("\(speed, specifier: "%.2g")x").tag(speed)
                }
            }
            .pickerStyle(.segmented)

            Stepper("Audio boost: \(viewModel.settings.playback.audioBoost, specifier: "%.2g")x", value: Binding(
                get: { viewModel.settings.playback.audioBoost },
                set: { value in Task { await viewModel.updateAudioBoost(value) } }
            ), in: 1...2.5, step: 0.25)

            Stepper("Seek step: \(viewModel.settings.playback.seekStepSeconds)s", value: Binding(
                get: { viewModel.settings.playback.seekStepSeconds },
                set: { value in Task { await viewModel.updateSeekStep(value) } }
            ), in: 5...60, step: 5)
        }
    }

    private var maxFileSizeLabel: String {
        guard let bytes = viewModel.settings.playback.maxFileSizeBytes, bytes > 0 else {
            return "Unlimited"
        }
        return "\(bytes / 1_000_000_000) GB"
    }

    private var maxFileSizeStepperTitle: String {
        "Max file size: \(maxFileSizeLabel)"
    }

    private var maxFileSizeGBBinding: Binding<Int> {
        Binding(
            get: { Int(viewModel.settings.playback.maxFileSizeBytes.map { $0 / 1_000_000_000 } ?? 0) },
            set: { value in Task { await viewModel.updateMaxFileSizeGB(value == 0 ? nil : Double(value)) } }
        )
    }

    private var subtitlesSection: some View {
        SettingsCard {
            Picker("Preferred subtitles", selection: Binding(
                get: { viewModel.subtitleSettings.languagePreference.languageCodes.joined(separator: ",") },
                set: { value in Task { await viewModel.updateSubtitleLanguages(value.split(separator: ",").map(String.init)) } }
            )) {
                Text("Russian -> English").tag("ru,en")
                Text("English -> Russian").tag("en,ru")
            }

            SettingsToggleRow(title: "Auto-load embedded subtitles", subtitle: "Prefer embedded/local subtitle tracks when available.", isOn: Binding(
                get: { viewModel.subtitleSettings.autoLoadSubtitles },
                set: { value in Task { await viewModel.updateAutoLoadEmbeddedSubtitles(value) } }
            ))
            SettingsToggleRow(title: "Auto-search OpenSubtitles", subtitle: "Search online subtitles when no local track matches.", isOn: Binding(
                get: { viewModel.subtitleSettings.autoSearchSubtitles },
                set: { value in Task { await viewModel.updateAutoSearchOpenSubtitles(value) } }
            ))

            Picker("Auto subtitle mode", selection: Binding(
                get: { viewModel.subtitleSettings.autoMode },
                set: { value in Task { await viewModel.updateSubtitleAutoMode(value) } }
            )) {
                ForEach(SubtitleAutoMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Stepper("Font size: \(Int(viewModel.subtitleSettings.fontSize))", value: Binding(
                get: { viewModel.subtitleSettings.fontSize },
                set: { value in Task { await viewModel.updateSubtitleFontSize(value) } }
            ), in: 24...72, step: 2)

            Stepper("Subtitle delay: \(viewModel.subtitleSettings.subtitleDelaySeconds, specifier: "%.1f")s", value: Binding(
                get: { viewModel.subtitleSettings.subtitleDelaySeconds },
                set: { value in Task { await viewModel.updateSubtitleDelay(value) } }
            ), in: -10...10, step: 0.5)

            Picker("Subtitle style", selection: Binding(
                get: { viewModel.subtitleSettings.visualStyle },
                set: { value in Task { await viewModel.updateSubtitleVisualStyle(value) } }
            )) {
                ForEach(SubtitleVisualStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Picker("Subtitle position", selection: Binding(
                get: { viewModel.subtitleSettings.placement },
                set: { value in Task { await viewModel.updateSubtitlePlacement(value) } }
            )) {
                ForEach(SubtitlePlacement.allCases) { placement in
                    Text(placement.title).tag(placement)
                }
            }
            .pickerStyle(.segmented)

            Divider().overlay(CFColors.separatorSubtle)

            HStack {
                Text("Cached subtitles")
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                Spacer()
                SecondaryButton("Reload", systemImage: "arrow.clockwise") {
                    Task { await viewModel.refreshCachedSubtitles() }
                }
            }

            if viewModel.cachedSubtitleItems.isEmpty {
                Text("Downloaded SRT and ASS files will appear here after playback or manual subtitle search.")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
            } else {
                ForEach(viewModel.cachedSubtitleItems) { item in
                    HStack(spacing: CFSpacing.sm) {
                        Image(systemName: "captions.bubble")
                            .foregroundStyle(CFColors.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.fileName)
                                .font(CFTypography.body)
                                .foregroundStyle(CFColors.textPrimary)
                            Text("\(item.languageCode.uppercased()) · \(item.fileExtension.uppercased()) · \(viewModel.cacheLabel(item.sizeBytes))")
                                .font(CFTypography.caption)
                                .foregroundStyle(CFColors.textMuted)
                        }
                        Spacer()
                        IconButton(systemImage: "trash", accessibilityLabel: "Delete cached subtitle") {
                            Task { await viewModel.deleteCachedSubtitle(id: item.id) }
                        }
                    }
                }
            }
        }
    }

    private var cacheSection: some View {
        SettingsCard {
            if viewModel.cacheSummary.isAlmostFull {
                CacheWarningBanner(
                    total: viewModel.cacheLabel(viewModel.cacheSummary.totalBytes),
                    limit: viewModel.cacheLabel(viewModel.cacheSummary.maxSizeBytes)
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: CFSpacing.md)], alignment: .leading, spacing: CFSpacing.md) {
                ForEach(viewModel.cacheSummary.buckets) { bucket in
                    CacheBucketCard(
                        title: cacheCategoryTitle(bucket.category),
                        systemImage: cacheCategoryIcon(bucket.category),
                        size: viewModel.cacheLabel(bucket.sizeBytes),
                        itemCount: bucket.itemCount,
                        path: bucket.path
                    ) {
                        Task { await clearCache(bucket.category) }
                    }
                    .help(cacheCategoryHelp(bucket.category))
                }
            }

            Divider().overlay(CFColors.separatorSubtle)

            VStack(alignment: .leading, spacing: CFSpacing.md) {
                Text("Auto-clean rules")
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)

                Picker("Remove cache older than", selection: Binding(
                    get: { viewModel.settings.storage.cacheRetentionDays },
                    set: { value in Task { await viewModel.updateCacheRetentionDays(value) } }
                )) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)

                Stepper(
                    "Max cache size: \(maxCacheSizeGB) GB",
                    value: Binding(
                        get: { maxCacheSizeGB },
                        set: { value in Task { await viewModel.updateMaxCacheSizeGB(value) } }
                    ),
                    in: 1...512,
                    step: 5
                )

                SettingsToggleRow(title: "Keep unfinished downloads", subtitle: "Active and incomplete torrent data is protected from cleanup.", isOn: Binding(
                    get: { viewModel.settings.storage.keepUnfinishedCache },
                    set: { value in Task { await viewModel.updateKeepUnfinishedCache(value) } }
                ))

                SettingsToggleRow(title: "Remove completed downloads", subtitle: "Completed torrent cache can be cleaned when retention or size rules apply.", isOn: Binding(
                    get: { viewModel.settings.storage.removeCompletedCache },
                    set: { value in Task { await viewModel.updateRemoveCompletedCache(value) } }
                ))

                Picker("Download bandwidth", selection: Binding(
                    get: { bandwidthMBps(viewModel.settings.storage.torrentDownloadLimitBytesPerSecond) },
                    set: { value in Task { await viewModel.updateTorrentDownloadLimitMBps(value == 0 ? nil : value) } }
                )) {
                    Text("Unlimited").tag(0)
                    Text("5 MB/s").tag(5)
                    Text("10 MB/s").tag(10)
                    Text("25 MB/s").tag(25)
                    Text("50 MB/s").tag(50)
                }
                .pickerStyle(.segmented)
                .help("Limit torrent download speed for new streaming sessions.")

                Picker("Upload bandwidth", selection: Binding(
                    get: { bandwidthMBps(viewModel.settings.storage.torrentUploadLimitBytesPerSecond) },
                    set: { value in Task { await viewModel.updateTorrentUploadLimitMBps(value == 0 ? nil : value) } }
                )) {
                    Text("Unlimited").tag(0)
                    Text("1 MB/s").tag(1)
                    Text("5 MB/s").tag(5)
                    Text("10 MB/s").tag(10)
                }
                .pickerStyle(.segmented)
                .help("Optionally limit torrent upload speed for new streaming sessions.")
            }

            Divider().overlay(CFColors.separatorSubtle)

            SettingValueRow(title: "Total cache", value: "\(viewModel.cacheLabel(viewModel.cacheSummary.totalBytes)) / \(viewModel.cacheLabel(viewModel.cacheSummary.maxSizeBytes))")
            SettingValueRow(title: "Torrent cache folder", value: viewModel.settings.storage.torrentCacheFolderPath)
            SettingValueRow(title: "Downloads folder", value: viewModel.settings.storage.downloadsFolderPath ?? "Default system downloads")

            HStack(spacing: CFSpacing.sm) {
                SecondaryButton("Choose cache folder", systemImage: "folder") { viewModel.chooseTorrentCacheFolder() }
                    .help(t(.tooltipCache))
                SecondaryButton("Run auto-clean", systemImage: "wand.and.stars") { Task { await viewModel.runCacheAutoClean() } }
                    .help("Apply retention, completed-download and max-size rules now.")
                SecondaryButton("Clear all cache", systemImage: "trash") { Task { await viewModel.clearAllCache() } }
                    .help(t(.tooltipCache))
            }

            VStack(alignment: .leading, spacing: CFSpacing.sm) {
                Text("Per-title cache")
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)

                if viewModel.cacheSummary.titleItems.isEmpty {
                    EmptyState(
                        title: "No cached titles",
                        message: "Streamly will show cached torrents, subtitles and metadata here after playback or browsing.",
                        systemImage: "externaldrive",
                        actionTitle: "Refresh",
                        actionSystemImage: "arrow.clockwise"
                    ) {
                        Task { await viewModel.refreshCacheSummary() }
                    }
                } else {
                    ForEach(viewModel.cacheSummary.titleItems) { item in
                        CacheTitleRow(
                            item: item,
                            sizeLabel: viewModel.cacheLabel(item.sizeBytes),
                            categoryTitle: cacheCategoryTitle(item.category)
                        ) {
                            Task { await viewModel.setTitleCacheKeepForLater(itemID: item.id, keep: !item.isKeptForLater) }
                        } clearAction: {
                            Task { await viewModel.clearTitleCache(itemID: item.id) }
                        }
                    }
                }
            }
        }
    }

    private var maxCacheSizeGB: Int {
        max(1, Int(viewModel.settings.storage.maxCacheSizeBytes / (1_024 * 1_024 * 1_024)))
    }

    private func bandwidthMBps(_ bytesPerSecond: Int64?) -> Int {
        guard let bytesPerSecond, bytesPerSecond > 0 else { return 0 }
        return Int(bytesPerSecond / (1_024 * 1_024))
    }

    private var updatesSection: some View {
        SettingsCard {
            SettingValueRow(title: "Current version", value: viewModel.about.version)
            SettingValueRow(title: "Current build", value: viewModel.about.build)
            SettingValueRow(title: "Release source", value: "GitHub Releases + Sparkle appcast")
            SettingValueRow(title: "Metadata attribution", value: "Movie and TV metadata is provided by TMDB and Cinemeta/Stremio.")
            SettingValueRow(title: "Last checked", value: lastUpdateCheckedText)
            SettingValueRow(title: "Updater status", value: viewModel.settings.updates.sparkleStatus)
            SettingValueRow(title: "Update status", value: updateStatusText)

            SettingsToggleRow(title: "Automatic update checks", subtitle: "Sparkle checks the appcast, offers the update and relaunches after install.", isOn: Binding(
                get: { viewModel.settings.updates.automaticChecksEnabled },
                set: { value in Task { await viewModel.updateAutomaticUpdateChecks(value) } }
            ))
            .help(t(.tooltipAutoUpdates))

            SecondaryButton("Check for updates", systemImage: "arrow.triangle.2.circlepath") {
                Task { await viewModel.checkForUpdates() }
            }
            .help(t(.tooltipAutoUpdates))
        }
    }

    private var lastUpdateCheckedText: String {
        guard let lastUpdateCheckedAt = viewModel.lastUpdateCheckedAt else { return t(.settingsUpdateNotChecked) }
        return lastUpdateCheckedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var diagnosticsSection: some View {
        SettingsCard {
            HStack(spacing: CFSpacing.sm) {
                SecondaryButton("Export diagnostics", systemImage: "square.and.arrow.up") { Task { await viewModel.exportDiagnostics() } }
                    .help(t(.tooltipDiagnostics))
                SecondaryButton("Open logs folder", systemImage: "folder") { viewModel.openLogsFolder() }
                    .help(t(.tooltipDiagnostics))
                SecondaryButton("Clear logs", systemImage: "trash") { viewModel.clearLogs() }
                    .help(t(.tooltipDiagnostics))
            }

            if let diagnosticsExport = viewModel.diagnosticsExport {
                Text(diagnosticsExport)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
            }
        }
    }

    private var privacySection: some View {
        SettingsCard {
            SettingValueRow(title: "Data model", value: "Local-only library, history, ratings and settings")
            SettingValueRow(title: "Telemetry", value: viewModel.settings.privacy.telemetryEnabled ? "Enabled" : "Off by default")
            Text("Credentials are stored in Keychain. SQLite settings keep only provider status and Keychain references.")
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textMuted)

            Divider().overlay(CFColors.separatorSubtle)

            libraryPortabilitySection

            Divider().overlay(CFColors.separatorSubtle)

            SettingsToggleRow(title: "Better release notifications", subtitle: "Notify when a 4K/HDR, healthier, better seeded or Russian-audio release appears.", isOn: Binding(
                get: { viewModel.settings.notifications.betterReleaseNotificationsEnabled },
                set: { value in Task { await viewModel.updateBetterReleaseNotificationsEnabled(value) } }
            ))

            SettingsToggleRow(title: "Digest mode", subtitle: "Group better release alerts in the in-app Notification Center instead of surfacing each one separately.", isOn: Binding(
                get: { viewModel.settings.notifications.betterReleaseDigestMode },
                set: { value in Task { await viewModel.updateBetterReleaseDigestMode(value) } }
            ))

            SettingsToggleRow(title: "macOS notifications", subtitle: "Optional system alerts for better releases. The in-app Notification Center remains primary.", isOn: Binding(
                get: { viewModel.settings.notifications.macOSBetterReleaseNotificationsEnabled },
                set: { value in Task { await viewModel.updateMacOSBetterReleaseNotificationsEnabled(value) } }
            ))

            Divider().overlay(CFColors.separatorSubtle)

            VStack(alignment: .leading, spacing: CFSpacing.sm) {
                Text("Notification categories")
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)

                ForEach(NotificationCategory.allCases) { category in
                    SettingsToggleRow(title: notificationCategoryTitle(category), subtitle: notificationCategorySubtitle(category), isOn: Binding(
                        get: { viewModel.settings.notifications.isCategoryEnabled(category) },
                        set: { value in Task { await viewModel.updateNotificationCategory(category, isEnabled: value) } }
                    ))
                }
            }

            SecondaryButton("Clear all local data", systemImage: "trash") {
                Task { await viewModel.clearAllLocalData() }
            }
        }
    }

    private var libraryPortabilitySection: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            Text("Library portability")
                .font(CFTypography.bodyEmphasis)
                .foregroundStyle(CFColors.textPrimary)

            HStack(spacing: CFSpacing.sm) {
                SecondaryButton("Export library", systemImage: "square.and.arrow.up") {
                    Task { await viewModel.exportLibrary() }
                }
                SecondaryButton("Import library", systemImage: "square.and.arrow.down") {
                    Task { await viewModel.chooseLibraryImportFile() }
                }
            }

            SettingsToggleRow(title: "Backup before import", subtitle: "Save current library JSON before applying imported data.", isOn: $viewModel.backupBeforeLibraryImport)

            if let preview = viewModel.libraryImportPreview {
                VStack(alignment: .leading, spacing: CFSpacing.sm) {
                    SettingValueRow(title: "Preview", value: preview.canImport ? "Ready to import" : "Validation failed")
                    SettingValueRow(title: "Records", value: libraryImportSummary(preview.summary))
                    SettingValueRow(title: "Duplicates", value: "\(preview.duplicateCount) will be merged")

                    if !preview.validationIssues.isEmpty {
                        ForEach(preview.validationIssues, id: \.self) { issue in
                            Text(issue)
                                .font(CFTypography.caption)
                                .foregroundStyle(CFColors.warning)
                        }
                    }

                    HStack(spacing: CFSpacing.sm) {
                        PrimaryButton("Import now", systemImage: "checkmark.circle") {
                            Task { await viewModel.confirmLibraryImport() }
                        }
                        .disabled(!preview.canImport)

                        SecondaryButton("Cancel import", systemImage: "xmark.circle") {
                            viewModel.cancelLibraryImport()
                        }
                    }
                }
                .padding(.top, CFSpacing.xs)
            }
        }
    }

    private var aboutSection: some View {
        SettingsCard {
            SettingValueRow(title: "App", value: viewModel.about.appName)
            SettingValueRow(title: "Version", value: "\(viewModel.about.version) (\(viewModel.about.build))")
            SettingValueRow(title: "Credits", value: viewModel.about.credits)
            SettingValueRow(title: "Licenses", value: viewModel.about.licenses)
        }
    }

    private var updateStatusText: String {
        switch viewModel.updateStatus {
        case .idle:
            t(.settingsUpdateIdle)
        case .checking:
            t(.settingsUpdateChecking)
        case .updateAvailable(let version):
            L10n.format(.settingsUpdateAvailableFormat, language: selectedLanguage, version)
        case .upToDate:
            t(.settingsUpdateUpToDate)
        case .failed:
            t(.settingsUpdateFailed)
        }
    }

    private func sectionDescription(_ section: SettingsSectionID) -> String {
        switch section {
        case .general: "Language, launch behavior and app startup preferences."
        case .appearance: "Dark visual system, accent color state and motion preference."
        case .home: "Personalized start page rows, density and poster sizing."
        case .tasteProfile: "Local taste signals for genres, people, formats and recommendation controls."
        case .sources: "TMDB metadata credentials and user-controlled playback source policy."
        case .playback: "Audio priority, resume behavior, acceleration and seeking."
        case .subtitles: "Subtitle language priority, loading behavior, size and timing."
        case .cache: "Local image, torrent and subtitle cache usage and cleanup."
        case .updates: "Version information and production Sparkle update controls."
        case .diagnostics: "Export diagnostics, inspect logs and clear log files."
        case .privacy: "Local-only data handling, telemetry default and local reset."
        case .about: "Application identity, credits and license information."
        }
    }

    private func libraryImportSummary(_ summary: LibraryImportSummary) -> String {
        "\(summary.libraryItems) library, \(summary.lists) lists, \(summary.watchHistory) history, \(summary.ratings) ratings, \(summary.playbackProgress) progress"
    }

    private func notificationCategoryTitle(_ category: NotificationCategory) -> String {
        switch category {
        case .betterRelease:
            "Better releases"
        case .newEpisode:
            "New episodes"
        case .sync:
            "Sync status"
        case .update:
            "App updates"
        case .sourceAuth:
            "Source authentication"
        case .cache:
            "Cache health"
        case .announcement:
            "Announcements"
        }
    }

    private func notificationCategorySubtitle(_ category: NotificationCategory) -> String {
        switch category {
        case .betterRelease:
            "4K/HDR, better seeded and Russian-audio release alerts."
        case .newEpisode:
            "New episodes and tracked-series availability."
        case .sync:
            "Local sync completed or failed states when account sync arrives."
        case .update:
            "Available app updates and release notices."
        case .sourceAuth:
            "Expired or invalid source sessions that need attention."
        case .cache:
            "Local cache warnings before storage becomes a problem."
        case .announcement:
            "Low-frequency product announcements inside Streamly."
        }
    }

    private func homeSectionTitle(_ sectionID: String) -> String {
        switch HomeSectionKind(rawValue: sectionID) {
        case .newEpisodes:
            return "New Episodes"
        case .upcomingCalendar:
            return "Upcoming Calendar"
        case .collections:
            return "Collections"
        case .moodDiscovery:
            return "What to Watch Today?"
        case .watchNext:
            return "Watch Next"
        case .continueWatching:
            return "Continue Watching"
        case .trendingNow:
            return "Trending Now"
        case .popularMovies:
            return "Popular Movies"
        case .popularSeries:
            return "Popular Series"
        case .trendingMovies:
            return "Trending Movies"
        case .trendingSeries:
            return "Trending Series"
        case .recentlyAdded:
            return "Recently Added"
        case .recommended:
            return "Because You Watched"
        case .moreLikeThis:
            return "More Like This"
        case .fromFavoriteGenres:
            return "From Your Favorite Genres"
        case .continueSeries:
            return "Continue Series"
        case .hiddenGems:
            return "Hidden Gems"
        case .popularInFavoriteGenres:
            return "Popular in Your Favorite Genres"
        case .notFinishedYet:
            return "Not Finished Yet"
        case .topQuality:
            return "Best Quality Available"
        case .ultraHDR:
            return "4K/HDR Available"
        case .favoriteGenres:
            return "Your Favorite Genres"
        case .unfinishedMovies:
            return "Unfinished Movies"
        case .forgottenInLibrary:
            return "Forgotten in Library"
        case .recommendedTonight:
            return "Recommended Tonight"
        case .none:
            return sectionID
        }
    }

    private func hiddenItemDetail(_ item: HiddenRecommendationItem) -> String {
        let genres = item.genres.isEmpty ? "No genre" : item.genres.joined(separator: ", ")
        return "\(item.reason.displayTitle) · \(genres)"
    }

    private func binding(_ dictionary: Binding<[String: String]>, _ key: String) -> Binding<String> {
        Binding(
            get: { dictionary.wrappedValue[key, default: ""] },
            set: { dictionary.wrappedValue[key] = $0 }
        )
    }

    private func copyToPasteboard(_ value: String?) {
        guard let value, !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func clearCache(_ category: SmartCacheCategory) async {
        switch category {
        case .images:
            await viewModel.clearImageCache()
        case .torrents:
            await viewModel.clearTorrentCache()
        case .subtitles:
            await viewModel.clearSubtitlesCache()
        case .timelinePreviews:
            await viewModel.clearTimelinePreviewCache()
        case .metadata:
            await viewModel.clearMetadataCache()
        }
    }

    private func cacheCategoryTitle(_ category: SmartCacheCategory) -> String {
        switch category {
        case .images: "Image cache"
        case .torrents: "Torrent cache"
        case .subtitles: "Subtitles cache"
        case .timelinePreviews: "Timeline previews"
        case .metadata: "Metadata cache"
        }
    }

    private func cacheCategoryIcon(_ category: SmartCacheCategory) -> String {
        switch category {
        case .images: "photo.on.rectangle"
        case .torrents: "arrow.down.doc"
        case .subtitles: "captions.bubble"
        case .timelinePreviews: "rectangle.stack"
        case .metadata: "database"
        }
    }

    private func cacheCategoryHelp(_ category: SmartCacheCategory) -> String {
        switch category {
        case .images: "Artwork files cached locally for faster browsing."
        case .torrents: "Torrent data is cleaned without touching active playback."
        case .subtitles: "Downloaded subtitle files stored locally."
        case .timelinePreviews: "Frame thumbnails generated lazily for timeline hover."
        case .metadata: "Local provider responses used for faster detail screens."
        }
    }

    private var selectedLanguage: AppLanguage {
        languageSettingsStore.selectedLanguage
    }

    private var tasteGenreRows: [String] {
        let defaults = ["Action", "Adventure", "Comedy", "Drama", "Fantasy", "Horror", "Mystery", "Romance", "Sci-Fi", "Thriller"]
        let custom = viewModel.settings.tasteProfile.genrePreferences.map(\.genre)
        return Array(Set(defaults + custom)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: selectedLanguage)
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            content
        }
        .padding(CFSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cfPanelBackground(fill: CFColors.panelFill, shadow: .panel)
    }
}

private struct CacheWarningBanner: View {
    let total: String
    let limit: String

    var body: some View {
        HStack(alignment: .center, spacing: CFSpacing.sm) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(CFColors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cache is almost full")
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                Text("\(total) used from \(limit). Run auto-clean or increase the cache limit.")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
            }
        }
        .padding(CFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CFColors.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .stroke(CFColors.warning.opacity(0.32), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct CacheBucketCard: View {
    let title: String
    let systemImage: String
    let size: String
    let itemCount: Int
    let path: String?
    let clearAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.sm) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(CFColors.accentSecondary)
                    .frame(width: 24)
                Spacer()
                Button(action: clearAction) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(CFColors.textMuted)
                .help("Clear \(title.lowercased())")
                .accessibilityLabel("Clear \(title)")
            }

            Text(title)
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textMuted)
            Text(size)
                .font(CFTypography.sectionTitle)
                .foregroundStyle(CFColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(itemCount == 1 ? "1 item" : "\(itemCount) items")
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textMuted)
            if let path {
                Text(path)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(CFSpacing.md)
        .frame(minHeight: 146, alignment: .topLeading)
        .background(CFColors.elevatedFill, in: RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .stroke(CFColors.separatorSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(size), \(itemCount) items")
    }
}

private struct CacheTitleRow: View {
    let item: SmartTitleCacheItem
    let sizeLabel: String
    let categoryTitle: String
    let keepAction: () -> Void
    let clearAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: CFSpacing.md) {
            Image(systemName: item.isActive ? "play.circle.fill" : "externaldrive")
                .foregroundStyle(item.isActive ? CFColors.success : CFColors.textMuted)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: CFSpacing.xs) {
                    Text(item.title)
                        .font(CFTypography.bodyEmphasis)
                        .foregroundStyle(CFColors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.isActive {
                        CacheMiniBadge("Active")
                    }
                    if !item.isCompleted {
                        CacheMiniBadge("Unfinished")
                    }
                }
                Text("\(categoryTitle) • \(sizeLabel)")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("Keep", isOn: Binding(
                get: { item.isKeptForLater },
                set: { _ in keepAction() }
            ))
            .toggleStyle(.checkbox)
            .help("Keep this cached data during automatic cleanup.")

            SecondaryButton("Clear", systemImage: "trash") {
                clearAction()
            }
            .disabled(item.isActive || item.isKeptForLater)
            .help(item.isActive ? "Active playback cache is protected." : "Clear cached data for this item.")
        }
        .padding(.vertical, CFSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

private struct CacheMiniBadge: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(CFTypography.overline)
            .foregroundStyle(CFColors.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(CFColors.accentSecondary.opacity(0.22), in: Capsule())
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Binding<Bool>

    var body: some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                Text(subtitle)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
            }
        }
        .help(subtitle)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

private struct SettingValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(CFTypography.body)
                .foregroundStyle(CFColors.textSecondary)
            Spacer()
            Text(value)
                .font(CFTypography.bodyEmphasis)
                .foregroundStyle(CFColors.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

private extension View {
    @ViewBuilder
    func settingsDivider(unlessLast: Bool) -> some View {
        self
        if unlessLast {
            Divider().overlay(CFColors.separatorSubtle)
        }
    }
}
