import CineFlowCore
import CineFlowDesignSystem
import SwiftUI

public struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @State private var selection: SettingsSectionID = .general
    @State private var sourceUsername: [String: String] = [:]
    @State private var sourcePassword: [String: String] = [:]
    @State private var sourceCookies: [String: String] = [:]

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

            SettingsToggleRow(title: "Open last screen on launch", subtitle: "Restore the last active CineFlow area after restart.", isOn: Binding(
                get: { viewModel.settings.general.openLastScreenOnLaunch },
                set: { value in Task { await viewModel.updateOpenLastScreenOnLaunch(value) } }
            ))
        }
    }

    private var appearanceSection: some View {
        SettingsCard {
            SettingsToggleRow(title: "Dark Mode only", subtitle: "CineFlow is locked to the dark design system.", isOn: .constant(viewModel.settings.appearance.darkModeOnly))
                .disabled(true)

            SettingValueRow(title: "Accent color", value: "Neon purple locked")

            SettingsToggleRow(title: "Reduce motion", subtitle: "Use calmer transitions where motion is optional.", isOn: Binding(
                get: { viewModel.settings.appearance.reduceMotion },
                set: { value in Task { await viewModel.updateReduceMotion(value) } }
            ))
        }
    }

    private var sourcesSection: some View {
        SettingsCard {
            if viewModel.sourceRows.isEmpty {
                EmptyState(title: "No sources configured", message: "Provider catalog is unavailable in this environment.", systemImage: "antenna.radiowaves.left.and.right.slash")
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

    private var playbackSection: some View {
        SettingsCard {
            Picker("Preferred audio", selection: Binding(
                get: { viewModel.settings.playback.preferredAudioLanguages.joined(separator: ",") },
                set: { value in Task { await viewModel.updatePreferredAudioLanguages(value.split(separator: ",").map(String.init)) } }
            )) {
                Text("Russian -> English").tag("ru,en")
                Text("English -> Russian").tag("en,ru")
            }

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

            Stepper("Seek step: \(viewModel.settings.playback.seekStepSeconds)s", value: Binding(
                get: { viewModel.settings.playback.seekStepSeconds },
                set: { value in Task { await viewModel.updateSeekStep(value) } }
            ), in: 5...60, step: 5)
        }
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

            Stepper("Font size: \(Int(viewModel.subtitleSettings.fontSize))", value: Binding(
                get: { viewModel.subtitleSettings.fontSize },
                set: { value in Task { await viewModel.updateSubtitleFontSize(value) } }
            ), in: 24...72, step: 2)

            Stepper("Subtitle delay: \(viewModel.subtitleSettings.subtitleDelaySeconds, specifier: "%.1f")s", value: Binding(
                get: { viewModel.subtitleSettings.subtitleDelaySeconds },
                set: { value in Task { await viewModel.updateSubtitleDelay(value) } }
            ), in: -10...10, step: 0.5)
        }
    }

    private var cacheSection: some View {
        SettingsCard {
            SettingValueRow(title: "Image cache", value: viewModel.cacheLabel(viewModel.cacheSummary.imageBytes))
            SettingValueRow(title: "Torrent cache", value: viewModel.cacheLabel(viewModel.cacheSummary.torrentBytes))
            SettingValueRow(title: "Subtitles cache", value: viewModel.cacheLabel(viewModel.cacheSummary.subtitleBytes))
            SettingValueRow(title: "Total", value: viewModel.cacheLabel(viewModel.cacheSummary.totalBytes))
            SettingValueRow(title: "Torrent cache folder", value: viewModel.settings.storage.torrentCacheFolderPath)
            SettingValueRow(title: "Downloads folder", value: viewModel.settings.storage.downloadsFolderPath ?? "Default system downloads")

            HStack(spacing: CFSpacing.sm) {
                SecondaryButton("Choose cache folder", systemImage: "folder") { viewModel.chooseTorrentCacheFolder() }
                SecondaryButton("Clear image cache", systemImage: "photo") { Task { await viewModel.clearImageCache() } }
                SecondaryButton("Clear torrent cache", systemImage: "arrow.down.doc") { Task { await viewModel.clearTorrentCache() } }
                SecondaryButton("Clear all cache", systemImage: "trash") { Task { await viewModel.clearAllCache() } }
            }
        }
    }

    private var updatesSection: some View {
        SettingsCard {
            SettingValueRow(title: "Current version", value: viewModel.about.version)
            SettingValueRow(title: "Current build", value: viewModel.about.build)
            SettingValueRow(title: "Appcast", value: "https://<github-pages-domain>/cineflow/appcast.xml")
            SettingValueRow(title: "Last checked", value: lastUpdateCheckedText)
            SettingValueRow(title: "Sparkle status", value: viewModel.settings.updates.sparkleStatus)
            SettingValueRow(title: "Update status", value: updateStatusText)

            SettingsToggleRow(title: "Automatic update checks", subtitle: "Sparkle can check the hosted appcast on its schedule.", isOn: Binding(
                get: { viewModel.settings.updates.automaticChecksEnabled },
                set: { value in Task { await viewModel.updateAutomaticUpdateChecks(value) } }
            ))

            SecondaryButton("Check for updates", systemImage: "arrow.triangle.2.circlepath") {
                Task { await viewModel.checkForUpdates() }
            }
        }
    }

    private var lastUpdateCheckedText: String {
        guard let lastUpdateCheckedAt = viewModel.lastUpdateCheckedAt else { return "Not checked yet" }
        return lastUpdateCheckedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var diagnosticsSection: some View {
        SettingsCard {
            HStack(spacing: CFSpacing.sm) {
                SecondaryButton("Export diagnostics", systemImage: "square.and.arrow.up") { Task { await viewModel.exportDiagnostics() } }
                SecondaryButton("Open logs folder", systemImage: "folder") { viewModel.openLogsFolder() }
                SecondaryButton("Clear logs", systemImage: "trash") { viewModel.clearLogs() }
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

            SecondaryButton("Clear all local data", systemImage: "trash") {
                Task { await viewModel.clearAllLocalData() }
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
        case .idle: "Idle"
        case .checking: "Checking"
        case .updateAvailable(let version): "Update available: \(version)"
        case .upToDate: "Up to date"
        case .failed(let message): message
        }
    }

    private func sectionDescription(_ section: SettingsSectionID) -> String {
        switch section {
        case .general: "Language, launch behavior and app startup preferences."
        case .appearance: "Dark visual system, accent color state and motion preference."
        case .sources: "Provider availability, authentication status and Keychain-backed sessions."
        case .playback: "Audio priority, resume behavior, acceleration and seeking."
        case .subtitles: "Subtitle language priority, loading behavior, size and timing."
        case .cache: "Local image, torrent and subtitle cache usage and cleanup."
        case .updates: "Version information and Sparkle-ready update controls."
        case .diagnostics: "Export diagnostics, inspect logs and clear log files."
        case .privacy: "Local-only data handling, telemetry default and local reset."
        case .about: "Application identity, credits and license information."
        }
    }

    private func binding(_ dictionary: Binding<[String: String]>, _ key: String) -> Binding<String> {
        Binding(
            get: { dictionary.wrappedValue[key, default: ""] },
            set: { dictionary.wrappedValue[key] = $0 }
        )
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
        .background(
            RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                .fill(CFColors.elevatedFill)
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
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
        }
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
