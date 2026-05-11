import CineFlowCore
import CineFlowDesignSystem
import CineFlowLocalization
import SwiftUI

struct ReleaseExplanationBadges: View {
    let ranked: RankedRelease
    let language: AppLanguage

    var body: some View {
        if !ranked.labels.isEmpty {
            HStack(spacing: CFSpacing.xs) {
                ForEach(Array(ranked.labels.prefix(3)), id: \.self) { label in
                    CFBadge(ReleaseExplanationFormatter(language: language).labelTitle(label), tone: labelTone(label))
                }
            }
        }
    }

    private func labelTone(_ label: ReleaseRankingLabel) -> CFBadgeTone {
        switch label {
        case .best, .best4K, .bestRussianAudio:
            .success
        case .fastest:
            .seeders
        case .smallest:
            .source
        }
    }
}

struct ReleaseExplanationSummary: View {
    let ranked: RankedRelease
    let language: AppLanguage

    var body: some View {
        let reasons = ReleaseExplanationFormatter(language: language).conciseReasons(for: ranked)
        if !reasons.isEmpty {
            Text(reasons.prefix(3).joined(separator: " · "))
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textMuted)
                .lineLimit(2)
        }
    }
}

struct ReleaseAdvancedDetails: View {
    let ranked: RankedRelease
    let title: String
    let language: AppLanguage

    var body: some View {
        DisclosureGroup(title) {
            VStack(alignment: .leading, spacing: CFSpacing.xs) {
                ForEach(ReleaseExplanationFormatter(language: language).advancedDetails(for: ranked), id: \.self) { detail in
                    Text(detail)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                }
            }
            .padding(.top, CFSpacing.xs)
        }
        .font(CFTypography.caption)
        .foregroundStyle(CFColors.textSecondary)
    }
}

func localizedReleaseTooltip(for ranked: RankedRelease, language: AppLanguage, rankingHelp: String) -> String {
    "\(ReleaseExplanationFormatter(language: language).tooltipExplanation(for: ranked))\n\(rankingHelp)"
}

private struct ReleaseExplanationFormatter {
    let language: AppLanguage

    func labelTitle(_ label: ReleaseRankingLabel) -> String {
        switch label {
        case .best:
            t(.releaseExplanationLabelBest)
        case .fastest:
            t(.releaseExplanationLabelFastest)
        case .smallest:
            t(.releaseExplanationLabelSmallest)
        case .bestRussianAudio:
            t(.releaseExplanationLabelBestRussianAudio)
        case .best4K:
            t(.releaseExplanationLabelBest4K)
        }
    }

    func conciseReasons(for ranked: RankedRelease) -> [String] {
        var values: [String] = []

        appendUnique(t(.releaseExplanationReasonBestOverall), to: &values, when: ranked.labels.contains(.best))
        appendUnique(t(.releaseExplanationReasonHighestSeeders), to: &values, when: ranked.labels.contains(.fastest))
        appendUnique(t(.releaseExplanationReasonSmallestFile), to: &values, when: ranked.labels.contains(.smallest))

        for reason in ranked.reasons {
            switch reason {
            case .quality(.ultraHD):
                appendUnique(t(.releaseExplanationReason4K), to: &values)
            case .quality(.fullHD):
                appendUnique(t(.releaseExplanationReason1080p), to: &values)
            case .quality(.hd):
                appendUnique(t(.releaseExplanationReason720p), to: &values)
            case .hdr(let hdr) where hdr != .none && hdr != .unknown:
                appendUnique(t(.releaseExplanationReasonHDR), to: &values)
            case .hdrPreference(.preferHDR):
                appendUnique(t(.releaseExplanationReasonHDR), to: &values)
            case .codec(.hevc), .codec(.h265), .codecPreference(.preferHEVC):
                appendUnique(t(.releaseExplanationReasonHEVC), to: &values)
            case .preferredAudioLanguage(let language) where Self.isRussian(language):
                appendUnique(t(.releaseExplanationReasonRussianAudio), to: &values)
            case .preferredAudioLanguage(let language):
                appendUnique(L10n.format(.releaseExplanationReasonAudioFormat, language: self.language, language.uppercased()), to: &values)
            case .preferredSubtitleLanguage(let language) where Self.isEnglish(language):
                appendUnique(t(.releaseExplanationReasonEnglishSubtitles), to: &values)
            case .preferredSubtitleLanguage(let language):
                appendUnique(L10n.format(.releaseExplanationReasonSubtitlesFormat, language: self.language, language.uppercased()), to: &values)
            case .trustedUploader:
                appendUnique(t(.releaseExplanationReasonTrustedSource), to: &values)
            case .releaseHealth(.excellent), .releaseHealth(.good):
                appendUnique(t(.releaseExplanationReasonHealthy), to: &values)
            case .fitsSizePreference:
                appendUnique(t(.releaseExplanationReasonFitsSize), to: &values)
            default:
                break
            }
        }

        return Array(values.prefix(9))
    }

    func tooltipExplanation(for ranked: RankedRelease) -> String {
        let reasons = conciseReasons(for: ranked)
        guard !reasons.isEmpty else {
            return L10n.format(.releaseExplanationTooltipScoreFormat, language: language, Int(ranked.score.rounded()))
        }
        return t(.releaseExplanationTooltipTitle) + "\n" + reasons.map { "• \($0)" }.joined(separator: "\n")
    }

    func advancedDetails(for ranked: RankedRelease) -> [String] {
        var details = [
            L10n.format(.releaseExplanationAdvancedScoreFormat, language: language, Int(ranked.score.rounded())),
            L10n.format(.releaseExplanationAdvancedSourceFormat, language: language, ranked.release.sourceName),
            L10n.format(.releaseExplanationAdvancedQualityFormat, language: language, ranked.release.qualityLabel),
            L10n.format(.releaseExplanationAdvancedSeedersFormat, language: language, ranked.release.seeders),
            L10n.format(.releaseExplanationAdvancedSizeFormat, language: language, ranked.release.humanReadableSize)
        ]

        if ranked.release.hdr != .none, ranked.release.hdr != .unknown {
            details.append(L10n.format(.releaseExplanationAdvancedHDRFormat, language: language, ranked.release.hdr.rawValue))
        }
        if ranked.release.codec != .unknown {
            details.append(L10n.format(.releaseExplanationAdvancedCodecFormat, language: language, ranked.release.codec.rawValue))
        }
        if !ranked.release.audioLanguages.isEmpty {
            details.append(L10n.format(.releaseExplanationAdvancedAudioFormat, language: language, ranked.release.audioLanguages.joined(separator: ", ")))
        }
        if !ranked.release.subtitleLanguages.isEmpty {
            details.append(L10n.format(.releaseExplanationAdvancedSubtitlesFormat, language: language, ranked.release.subtitleLanguages.joined(separator: ", ")))
        }
        details.append(L10n.format(.releaseExplanationAdvancedHealthFormat, language: language, healthTitle(ranked.release.releaseHealth)))
        return details
    }

    private func healthTitle(_ health: ReleaseHealth) -> String {
        switch health {
        case .excellent:
            t(.releaseHealthExcellent)
        case .good:
            t(.releaseHealthGood)
        case .weak:
            t(.releaseHealthWeak)
        case .noSeeders:
            t(.releaseHealthNoSeeders)
        case .unknown:
            t(.releaseHealthUnknown)
        }
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: language)
    }

    private static func isRussian(_ language: String) -> Bool {
        let normalized = language.lowercased()
        return normalized == "ru" || normalized == "rus" || normalized.contains("russian")
    }

    private static func isEnglish(_ language: String) -> Bool {
        let normalized = language.lowercased()
        return normalized == "en" || normalized == "eng" || normalized.contains("english")
    }

    private func appendUnique(_ value: String, to values: inout [String], when condition: Bool = true) {
        guard condition, !values.contains(value) else { return }
        values.append(value)
    }
}
