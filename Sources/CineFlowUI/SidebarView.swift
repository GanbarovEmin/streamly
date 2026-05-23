import CineFlowDesignSystem
import CineFlowLocalization
import Foundation
import SwiftUI

public struct SidebarFooterContent: Equatable {
    public let title: String
    public let versionSummary: String

    public var detail: String {
        detail(prefix: "Version")
    }

    public init(
        version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
        build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"
    ) {
        title = "Streamly"
        versionSummary = Self.versionSummary(version: version, build: build)
    }

    public func detail(prefix: String) -> String {
        "\(prefix) \(versionSummary)"
    }

    private static func versionSummary(version: String, build: String) -> String {
        let normalizedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBuild = build.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayVersion = normalizedVersion.isEmpty ? "0.1.0" : normalizedVersion
        guard !normalizedBuild.isEmpty else {
            return displayVersion
        }
        return "\(displayVersion) (\(normalizedBuild))"
    }
}

public struct SidebarView: View {
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore
    @Environment(\.cfReduceMotion) private var reduceMotion
    private let footerContent: SidebarFooterContent

    public init(
        navigationCoordinator: NavigationCoordinator,
        footerContent: SidebarFooterContent = SidebarFooterContent()
    ) {
        self.navigationCoordinator = navigationCoordinator
        self.footerContent = footerContent
    }

    public var body: some View {
        ZStack {
            SidebarVibrancyBackground()
                .overlay(CFColors.backgroundPrimary.opacity(CFBlur.sidebarOverlayOpacity))
                .overlay(
                    LinearGradient(
                        colors: [
                            CFColors.backgroundTertiary.opacity(0.42),
                            CFColors.backgroundPrimary.opacity(0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(alignment: .leading, spacing: CFSpacing.xl) {
                brand
                    .padding(.top, 36)
                    .padding(.horizontal, 28)

                VStack(spacing: CFSpacing.sm) {
                    ForEach(AppRoute.sidebarRoutes) { item in
                        SidebarItem(
                            title: L10n.string(item.titleKey, language: languageSettingsStore.selectedLanguage),
                            systemImage: item.systemImage,
                            isSelected: item == navigationCoordinator.selectedSidebarRoute
                        ) {
                            withAnimation(reduceMotion ? nil : CFMotion.spring) {
                                navigationCoordinator.selectSidebarRoute(item)
                            }
                        }
                        .help(L10n.string(item.titleKey, language: languageSettingsStore.selectedLanguage))
                        .accessibilityLabel(L10n.string(item.titleKey, language: languageSettingsStore.selectedLanguage))
                    }
                }
                .padding(.horizontal, 16)

                Spacer()

                sidebarFooter
                    .padding(.horizontal, 24)
                    .padding(.bottom, 26)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(CFColors.separatorSubtle)
                .frame(width: CFSeparators.width)
        }
        .focusable(true)
        .onMoveCommand(perform: moveSelection)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let routes = AppRoute.sidebarRoutes
        guard let currentIndex = routes.firstIndex(of: navigationCoordinator.selectedSidebarRoute) else {
            navigationCoordinator.selectSidebarRoute(.home)
            return
        }

        switch direction {
        case .up:
            let nextIndex = max(routes.startIndex, currentIndex - 1)
            navigationCoordinator.selectSidebarRoute(routes[nextIndex])
        case .down:
            let nextIndex = min(routes.index(before: routes.endIndex), currentIndex + 1)
            navigationCoordinator.selectSidebarRoute(routes[nextIndex])
        default:
            break
        }
    }

    private var brand: some View {
        HStack(spacing: CFSpacing.md) {
            CFBrandMark(size: 40)

            VStack(alignment: .leading, spacing: CFSpacing.xxs) {
                Text(L10n.string(.appName, language: languageSettingsStore.selectedLanguage))
                    .font(.system(size: 19, weight: .semibold, design: .default))
                    .foregroundStyle(CFColors.textPrimary)

                Text(L10n.string(.sidebarTagline, language: languageSettingsStore.selectedLanguage))
                    .font(CFTypography.overline)
                    .foregroundStyle(CFColors.textMuted)
            }
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: CFSpacing.sm) {
            Text(footerContent.title)
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textSecondary)

            Text(footerContent.detail(prefix: L10n.string(.sidebarRuntimeMessage, language: languageSettingsStore.selectedLanguage)))
                .font(CFTypography.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(CFColors.textMuted)
        }
        .padding(CFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .fill(CFColors.panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
    }
}
