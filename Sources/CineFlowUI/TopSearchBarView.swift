import CineFlowDesignSystem
import CineFlowLocalization
import SwiftUI

public struct TopSearchBarView: View {
    public let controls: [ShellTopControl]
    public let focusRequestID: Int
    public let queryText: String
    public let isLoading: Bool
    public let controlBadges: [String: Int]
    public let onQueryChange: (String) -> Void
    public let onClear: () -> Void
    public let onSearchFocus: () -> Void
    public let onControlAction: (ShellTopControl) -> Void

    @FocusState private var isSearchFocused: Bool
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    public init(
        controls: [ShellTopControl],
        focusRequestID: Int,
        queryText: String = "",
        isLoading: Bool = false,
        controlBadges: [String: Int] = [:],
        onQueryChange: @escaping (String) -> Void = { _ in },
        onClear: @escaping () -> Void = {},
        onSearchFocus: @escaping () -> Void = {},
        onControlAction: @escaping (ShellTopControl) -> Void = { _ in }
    ) {
        self.controls = controls
        self.focusRequestID = focusRequestID
        self.queryText = queryText
        self.isLoading = isLoading
        self.controlBadges = controlBadges
        self.onQueryChange = onQueryChange
        self.onClear = onClear
        self.onSearchFocus = onSearchFocus
        self.onControlAction = onControlAction
    }

    public var body: some View {
        HStack(spacing: CFSpacing.md) {
            searchField

            Spacer(minLength: CFSpacing.lg)

            HStack(spacing: CFSpacing.sm) {
                ForEach(controls) { control in
                    ZStack(alignment: .topTrailing) {
                        IconButton(
                            systemImage: control.systemImage,
                            accessibilityLabel: L10n.string(control.titleKey, language: languageSettingsStore.selectedLanguage)
                        ) {
                            onControlAction(control)
                        }

                        if let badge = controlBadges[control.id], badge > 0 {
                            Text("\(min(badge, 99))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(CFColors.textPrimary)
                                .frame(minWidth: 15, minHeight: 15)
                                .background(Capsule().fill(CFColors.accentPrimary))
                                .offset(x: 5, y: -5)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .padding(.leading, CFSpacing.xl)
        .padding(.trailing, CFSpacing.xl)
        .padding(.top, CFSpacing.md)
        .padding(.bottom, CFSpacing.md)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                CFColors.backgroundPrimary.opacity(0.72)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CFColors.separator)
                .frame(height: CFSeparators.width)
                .allowsHitTesting(false)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CFColors.textMuted)

            TextField(
                L10n.string(.searchPlaceholder, language: languageSettingsStore.selectedLanguage),
                text: Binding(
                    get: { queryText },
                    set: { onQueryChange($0) }
                )
            )
                .textFieldStyle(.plain)
                .font(CFTypography.callout)
                .foregroundStyle(CFColors.textPrimary)
                .tint(CFColors.accentPrimary)
                .focused($isSearchFocused)
                .onSubmit(onSearchFocus)
                .accessibilityLabel(L10n.string(.commandSearch, language: languageSettingsStore.selectedLanguage))
                .accessibilityHint(L10n.string(.commandFocusSearch, language: languageSettingsStore.selectedLanguage))

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
                    .accessibilityLabel(L10n.string(.searchStateLoading, language: languageSettingsStore.selectedLanguage))
            } else if !queryText.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CFColors.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string(.searchClear, language: languageSettingsStore.selectedLanguage))
                .help(L10n.string(.searchClear, language: languageSettingsStore.selectedLanguage))
            }
        }
        .padding(.horizontal, 15)
        .frame(width: 440, height: 42)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .fill(CFColors.backgroundSecondary.opacity(0.76))
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                        .stroke(isSearchFocused ? CFColors.focusRing.opacity(0.62) : CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
        .overlay(alignment: .bottomLeading) {
            if isSearchFocused {
                Capsule()
                    .fill(CFColors.horizontalGradient)
                    .frame(width: 104, height: 2)
                    .padding(.leading, 16)
                    .padding(.bottom, 4)
            }
        }
        .help(L10n.string(.searchPlaceholder, language: languageSettingsStore.selectedLanguage))
        .onTapGesture {
            isSearchFocused = true
            onSearchFocus()
        }
        .onChange(of: focusRequestID) { _ in
            isSearchFocused = true
        }
    }
}
