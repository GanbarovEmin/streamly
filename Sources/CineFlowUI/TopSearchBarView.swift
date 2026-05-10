import CineFlowDesignSystem
import CineFlowLocalization
import SwiftUI

public struct TopSearchBarView: View {
    public let controls: [ShellTopControl]
    public let focusRequestID: Int
    public let queryText: String
    public let onQueryChange: (String) -> Void
    public let onSearchFocus: () -> Void

    @FocusState private var isSearchFocused: Bool
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    public init(
        controls: [ShellTopControl],
        focusRequestID: Int,
        queryText: String = "",
        onQueryChange: @escaping (String) -> Void = { _ in },
        onSearchFocus: @escaping () -> Void = {}
    ) {
        self.controls = controls
        self.focusRequestID = focusRequestID
        self.queryText = queryText
        self.onQueryChange = onQueryChange
        self.onSearchFocus = onSearchFocus
    }

    public var body: some View {
        HStack(spacing: 18) {
            searchField

            Spacer(minLength: 24)

            HStack(spacing: 10) {
                ForEach(controls) { control in
                    IconButton(
                        systemImage: control.systemImage,
                        accessibilityLabel: L10n.string(control.titleKey, language: languageSettingsStore.selectedLanguage)
                    ) {}
                }
            }
        }
        .padding(.leading, 30)
        .padding(.trailing, 28)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
        .overlay(CFColors.backgroundPrimary.opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CFColors.separator)
                .frame(height: CFSeparators.width)
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
        .onTapGesture(perform: onSearchFocus)
        .onChange(of: focusRequestID) { _ in
            isSearchFocused = true
        }
    }
}
