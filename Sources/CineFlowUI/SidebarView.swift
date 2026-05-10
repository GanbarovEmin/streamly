import CineFlowDesignSystem
import CineFlowLocalization
import SwiftUI

public struct SidebarView: View {
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    public init(navigationCoordinator: NavigationCoordinator) {
        self.navigationCoordinator = navigationCoordinator
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
                            withAnimation(CFMotion.spring) {
                                navigationCoordinator.selectSidebarRoute(item)
                            }
                        }
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
            Text(L10n.string(.sidebarRuntimeTitle, language: languageSettingsStore.selectedLanguage))
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textSecondary)

            Text(L10n.string(.sidebarRuntimeMessage, language: languageSettingsStore.selectedLanguage))
                .font(CFTypography.caption)
                .lineLimit(2)
                .foregroundStyle(CFColors.textMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .fill(CFColors.elevatedFill)
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
    }
}
