import CineFlowCore
import CineFlowDesignSystem
import CineFlowLocalization
import CineFlowSources
import SwiftUI

private struct SourceProviderSettingsRow: Identifiable, Equatable {
    let id: String
    let displayName: String
    let requiresAuthentication: Bool
    var settings: SourceSettings
}

@MainActor
private final class SourceSettingsViewModel: ObservableObject {
    @Published private(set) var rows: [SourceProviderSettingsRow] = []
    @Published private(set) var error: CineFlowError?

    private let manager: SourceManager

    init(manager: SourceManager) {
        self.manager = manager
    }

    func load() async {
        do {
            let descriptors = await manager.providerDescriptors()
            var rows: [SourceProviderSettingsRow] = []
            for descriptor in descriptors {
                let settings = try await manager.settings(for: descriptor.sourceId)
                rows.append(
                    SourceProviderSettingsRow(
                        id: descriptor.sourceId,
                        displayName: descriptor.displayName,
                        requiresAuthentication: descriptor.requiresAuthentication,
                        settings: settings
                    )
                )
            }
            self.rows = rows
            error = nil
        } catch {
            self.error = CineFlowError.from(error, fallbackCategory: .source)
        }
    }

    func setEnabled(_ isEnabled: Bool, sourceId: String) {
        Task {
            do {
                try await manager.setSourceEnabled(isEnabled, sourceId: sourceId)
                await load()
            } catch {
                self.error = CineFlowError.from(error, fallbackCategory: .source)
            }
        }
    }
}

struct SourceSettingsCard: View {
    @StateObject private var viewModel: SourceSettingsViewModel
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    init(manager: SourceManager) {
        _viewModel = StateObject(wrappedValue: SourceSettingsViewModel(manager: manager))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: CFSpacing.xs) {
                    Text(t(.sourcesHeaderTitle))
                        .font(CFTypography.bodyEmphasis)
                        .foregroundStyle(CFColors.textPrimary)
                    Text(t(.sourcesHeaderSubtitle))
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                }

                Spacer()

                Text("\(viewModel.rows.filter(\.settings.isEnabled).count)/\(viewModel.rows.count)")
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                    .monospacedDigit()
            }

            if viewModel.error != nil {
                ErrorState(
                    title: t(.sourcesErrorTitle),
                    message: t(.sourcesErrorMessage),
                    recoverySuggestion: t(.sourcesErrorRecovery),
                    actionTitle: t(.commonRetry)
                ) {
                    Task { await viewModel.load() }
                }
            }

            if viewModel.rows.isEmpty, viewModel.error == nil {
                EmptyState(
                    title: t(.sourcesEmptyTitle),
                    message: t(.sourcesEmptyMessage),
                    systemImage: "externaldrive",
                    actionTitle: t(.commonRetry),
                    actionSystemImage: "arrow.clockwise"
                ) {
                    Task { await viewModel.load() }
                }
            } else {
                VStack(spacing: CFSpacing.sm) {
                    ForEach(viewModel.rows) { row in
                        SourceProviderToggleRow(
                            row: row,
                            language: selectedLanguage,
                            onToggle: { isEnabled in
                                viewModel.setEnabled(isEnabled, sourceId: row.id)
                            }
                        )
                    }
                }
            }
        }
        .padding(CFSpacing.lg)
        .cfPanelBackground(fill: CFColors.panelFill, shadow: .panel)
        .task {
            await viewModel.load()
        }
    }

    private var selectedLanguage: AppLanguage {
        languageSettingsStore.selectedLanguage
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: selectedLanguage)
    }
}

private struct SourceProviderToggleRow: View {
    let row: SourceProviderSettingsRow
    let language: AppLanguage
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: CFSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: CFSpacing.sm) {
                    Text(row.displayName)
                        .font(CFTypography.bodyEmphasis)
                        .foregroundStyle(CFColors.textPrimary)

                    Text(statusBadgeLabel)
                        .font(CFTypography.caption)
                        .foregroundStyle(healthForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(healthForeground.opacity(0.14), in: Capsule())

                    if row.requiresAuthentication {
                        Text(authenticationLabel)
                            .font(CFTypography.caption)
                            .foregroundStyle(CFColors.textMuted)
                    }
                }

                Text(statusLabel)
                    .font(CFTypography.caption)
                    .foregroundStyle(row.settings.errorState == nil ? CFColors.textMuted : CFColors.error)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { row.settings.isEnabled },
                set: onToggle
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, CFSpacing.xs)
    }

    private var authenticationLabel: String {
        switch row.settings.authenticationStatus {
        case .authenticated(let username):
            return username.map { L10n.format(.sourcesAuthAuthenticatedFormat, language: language, $0) }
                ?? L10n.string(.sourcesAuthAuthenticated, language: language)
        case .invalid:
            return L10n.string(.sourcesAuthInvalid, language: language)
        case .notRequired:
            return L10n.string(.sourcesAuthNotRequired, language: language)
        case .unauthenticated:
            return L10n.string(.sourcesAuthRequired, language: language)
        }
    }

    private var statusLabel: String {
        if let error = row.settings.errorState {
            return [
                L10n.format(.sourcesStatusErrorFormat, language: language, error.message),
                successRateLabel
            ].joined(separator: " · ")
        }
        if let lastSyncAt = row.settings.lastSyncAt {
            return [
                L10n.format(.sourcesStatusLastSyncFormat, language: language, formatted(lastSyncAt)),
                successRateLabel
            ].joined(separator: " · ")
        }
        if let lastCheckedAt = row.settings.lastCheckedAt {
            return [
                L10n.format(.sourcesStatusLastCheckFormat, language: language, formatted(lastCheckedAt)),
                successRateLabel
            ].joined(separator: " · ")
        }
        return successRateLabel
    }

    private var statusBadgeLabel: String {
        switch row.settings.sourceStatus {
        case .online:
            return L10n.string(.sourcesHealthHealthy, language: language)
        case .disabled:
            return L10n.string(.sourcesHealthDisabled, language: language)
        case .authRequired:
            return L10n.string(.sourcesHealthNeedsAuthentication, language: language)
        case .slow:
            return L10n.string(.sourcesHealthDegraded, language: language)
        case .error:
            return L10n.string(.sourcesHealthUnavailable, language: language)
        }
    }

    private var healthForeground: Color {
        switch row.settings.sourceStatus {
        case .online:
            return CFColors.success
        case .disabled:
            return CFColors.textMuted
        case .authRequired, .slow:
            return CFColors.warning
        case .error:
            return CFColors.error
        }
    }

    private var successRateLabel: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        let value = formatter.string(from: NSNumber(value: row.settings.successRate)) ?? "\(Int(row.settings.successRate * 100))%"
        return L10n.format(.sourcesStatusSuccessRateFormat, language: language, value)
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
