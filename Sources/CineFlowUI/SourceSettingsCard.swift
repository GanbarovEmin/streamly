import CineFlowCore
import CineFlowDesignSystem
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

    init(manager: SourceManager) {
        _viewModel = StateObject(wrappedValue: SourceSettingsViewModel(manager: manager))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: CFSpacing.xs) {
                    Text("Torrent Sources")
                        .font(CFTypography.bodyEmphasis)
                        .foregroundStyle(CFColors.textPrimary)
                    Text("Enable isolated release providers. Credentials are stored in Keychain, not SQLite.")
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                }

                Spacer()

                Text("\(viewModel.rows.filter(\.settings.isEnabled).count)/\(viewModel.rows.count)")
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                    .monospacedDigit()
            }

            if let error = viewModel.error {
                InlineErrorState(error)
            }

            VStack(spacing: CFSpacing.sm) {
                ForEach(viewModel.rows) { row in
                    SourceProviderToggleRow(
                        row: row,
                        onToggle: { isEnabled in
                            viewModel.setEnabled(isEnabled, sourceId: row.id)
                        }
                    )
                }
            }
        }
        .padding(CFSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                .fill(CFColors.elevatedFill)
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
        .task {
            await viewModel.load()
        }
    }
}

private struct SourceProviderToggleRow: View {
    let row: SourceProviderSettingsRow
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: CFSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: CFSpacing.sm) {
                    Text(row.displayName)
                        .font(CFTypography.bodyEmphasis)
                        .foregroundStyle(CFColors.textPrimary)

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
            return username.map { "Authenticated: \($0)" } ?? "Authenticated"
        case .invalid:
            return "Auth invalid"
        case .notRequired:
            return "No auth"
        case .unauthenticated:
            return "Auth required"
        }
    }

    private var statusLabel: String {
        if let error = row.settings.errorState {
            return error.isRecoverable ? "Source needs attention" : "Source is unavailable"
        }
        if let lastSyncAt = row.settings.lastSyncAt {
            return "Last sync: \(lastSyncAt.formatted(date: .abbreviated, time: .shortened))"
        }
        if let lastCheckedAt = row.settings.lastCheckedAt {
            return "Last check: \(lastCheckedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return row.settings.isEnabled ? "Enabled" : "Disabled"
    }
}
