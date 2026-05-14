import CineFlowCore
import CineFlowDesignSystem
import CineFlowLocalization
import CineFlowPlayback
import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers

public struct PlayerView: View {
    @StateObject private var viewModel: PlayerViewModel
    @State private var timelineScrubTime: Double?
    @State private var isScrubbingTimeline = false
    @State private var timelineHoverX: CGFloat?
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore
    @Environment(\.cfReduceMotion) private var reduceMotion
    private let onExit: () -> Void
    private let onNextEpisode: (PlayerNextEpisodeAction) -> Void

    public init(
        viewModel: PlayerViewModel,
        onExit: @escaping () -> Void,
        onNextEpisode: @escaping (PlayerNextEpisodeAction) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onExit = onExit
        self.onNextEpisode = onNextEpisode
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            cinematicPlayerBackground
                .ignoresSafeArea()

            playerRenderSurface
                .overlay(Color.black.opacity(viewModel.dimBackgroundAroundVideo ? CFCinematicStyle.dimmedPlayerOpacity : 0).allowsHitTesting(false))
                .overlay(alignment: .top) {
                    CinematicScrim(edge: .top)
                        .frame(height: viewModel.controlsAreVisible ? 190 : 86)
                        .opacity(viewModel.controlsAreVisible ? 1 : 0.34)
                        .cfAnimation(CFMotion.cinematic, value: viewModel.controlsAreVisible, reduceMotion: reduceMotion)
                }
                .overlay(alignment: .bottom) {
                    CinematicScrim(edge: .bottom)
                        .frame(height: viewModel.controlsAreVisible ? 250 : 118)
                        .opacity(viewModel.controlsAreVisible ? 1 : 0.42)
                        .cfAnimation(CFMotion.cinematic, value: viewModel.controlsAreVisible, reduceMotion: reduceMotion)
                }
                .overlay(renderOverlay)
                .overlay(mouseActivityOverlay)
                .overlay(keyboardInput)
                .ignoresSafeArea()

            subtitleOverlay
                .padding(.bottom, viewModel.controlsAreVisible ? 174 : 42)
                .opacity(viewModel.activeSubtitleText == nil ? 0 : 1)
                .allowsHitTesting(false)
                .cfAnimation(CFMotion.standard, value: viewModel.controlsAreVisible, reduceMotion: reduceMotion)

            controls
                .opacity(viewModel.controlsAreVisible ? 1 : 0)
                .offset(y: viewModel.controlsAreVisible ? 0 : 18)
                .allowsHitTesting(viewModel.controlsAreVisible)
                .cfAnimation(CFMotion.standard, value: viewModel.controlsAreVisible, reduceMotion: reduceMotion)
        }
        .background(CFColors.backgroundPrimary)
        .onHover { hovering in
            if hovering {
                showCinematicControls()
            }
        }
        .onTapGesture {
            showCinematicControls()
        }
        .task {
            await viewModel.start()
            showCinematicControls()
        }
        .onDisappear {
            Task { await viewModel.saveProgressOnClose() }
        }
        .focusable()
        .keyboardShortcut(.space, modifiers: [])
    }

    private var keyboardInput: some View {
        PlayerKeyboardInputView { shortcut in
            switch shortcut {
            case .escape:
                Task { await viewModel.stop() }
                onExit()
            default:
                Task { await viewModel.handleShortcut(shortcut) }
            }
        }
        .frame(width: 0, height: 0)
    }

    private var mouseActivityOverlay: some View {
        PlayerMouseActivityView {
            showCinematicControls()
        }
    }

    private func showCinematicControls() {
        viewModel.showControlsTemporarily(autoHideAfter: CFCinematicStyle.playerControlAutoHideDelay)
    }

    private var cinematicPlayerBackground: some View {
        ZStack {
            CFColors.backgroundPrimary
            CinematicAmbientGlow(reduceMotion: reduceMotion)
                .opacity(viewModel.dimBackgroundAroundVideo ? 1 : 0.64)
        }
    }

    @ViewBuilder
    private var playerRenderSurface: some View {
        if let player = viewModel.avPlayer {
            AVPlayerRenderView(player: player)
        } else {
            MPVRenderView()
        }
    }

    private var renderOverlay: some View {
        VStack {
            HStack(spacing: CFSpacing.md) {
                HStack(spacing: CFSpacing.md) {
                    backButton

                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.status.media?.title ?? t(.playerTitleFallback))
                            .font(CFTypography.bodyEmphasis)
                            .foregroundStyle(CFColors.textPrimary)
                            .lineLimit(1)

                        Text(sourceInfo)
                            .font(CFTypography.caption)
                            .foregroundStyle(CFColors.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, CFSpacing.md)
                .frame(height: 54)
                .cinematicChrome(in: Capsule())
                .opacity(viewModel.controlsAreVisible ? 1 : 0)
                .allowsHitTesting(viewModel.controlsAreVisible)
                .cfAnimation(CFMotion.cinematic, value: viewModel.controlsAreVisible, reduceMotion: reduceMotion)

                Spacer()

                if let suggestion = viewModel.fallbackSuggestion {
                    fallbackCard(suggestion)
                } else if viewModel.errorMessage != nil {
                    ErrorState(
                        title: t(.playerPlaybackErrorTitle),
                        message: t(.playerPlaybackErrorMessage),
                        recoverySuggestion: t(.playerPlaybackErrorRecovery),
                        actionTitle: t(.playerMissingSourceAction),
                        action: onExit
                    )
                }
            }
            .padding(CFSpacing.xl)

            Spacer()

            VStack(spacing: CFSpacing.md) {
                if let resumePrompt = viewModel.resumePrompt {
                    resumePromptCard(resumePrompt)
                }

                if case .buffering(let progress) = viewModel.status.bufferingState {
                    bufferingCard(progress: progress)
                }

                if let nextEpisodePrompt = viewModel.nextEpisodePrompt {
                    nextEpisodeCard(nextEpisodePrompt)
                }
            }
            .padding(.bottom, 112)
        }
    }

    @ViewBuilder
    private var subtitleOverlay: some View {
        if let text = viewModel.activeSubtitleText, !text.isEmpty {
            Text(text)
                .font(.system(size: viewModel.status.subtitleFontSize, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.95), radius: 2, x: 0, y: 1)
                .shadow(color: .black.opacity(0.85), radius: 5, x: 0, y: 2)
                .padding(.horizontal, CFSpacing.xl)
                .padding(.vertical, CFSpacing.sm)
                .frame(maxWidth: 980)
        }
    }

    private var backButton: some View {
        IconButton(systemImage: "chevron.left", accessibilityLabel: t(.playerControlBack)) {
            Task { await viewModel.stop() }
            onExit()
        }
    }

    private func resumePromptCard(_ prompt: PlayerResumePrompt) -> some View {
        VStack(alignment: .leading, spacing: CFSpacing.sm) {
            Text(t(.playerResumeTitle))
                .font(CFTypography.title)
                .foregroundStyle(CFColors.textPrimary)

            Text(L10n.format(.playerResumeMessageFormat, language: languageSettingsStore.selectedLanguage, prompt.positionLabel))
                .font(CFTypography.body)
                .foregroundStyle(CFColors.textSecondary)

            HStack(spacing: CFSpacing.sm) {
                PrimaryButton(t(.playerResumeContinue), systemImage: "play.fill") {
                    Task { await viewModel.continueFromResume() }
                }
                SecondaryButton(t(.playerResumeStartOver), systemImage: "gobackward") {
                    Task { await viewModel.startOverFromBeginning() }
                }
            }
        }
        .padding(CFSpacing.lg)
        .frame(width: 420, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .stroke(CFColors.separator, lineWidth: CFSeparators.width)
        )
        .cfShadow(.elevated)
    }

    private func bufferingCard(progress: Double) -> some View {
        let presentation = viewModel.bufferingPresentation
        let displayedProgress = presentation.progress ?? progress
        return VStack(alignment: .leading, spacing: CFSpacing.sm) {
            HStack(spacing: CFSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text(t(.playerBufferingTitle))
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                Spacer()
                Text("\(Int(displayedProgress * 100))%")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
                    .monospacedDigit()
            }

            ProgressBar(value: displayedProgress)
                .frame(height: 5)

            Text(presentation.message.isEmpty
                 ? L10n.format(.playerBufferingMessageFormat, language: languageSettingsStore.selectedLanguage, Int(displayedProgress * 100))
                 : presentation.message)
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textSecondary)

            if !presentation.primaryDetails.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(presentation.primaryDetails, id: \.self) { detail in
                        Text(detail)
                            .font(CFTypography.caption)
                            .foregroundStyle(CFColors.textSecondary)
                            .monospacedDigit()
                    }
                }
            }

            Toggle(t(.playerAdvancedDetails), isOn: Binding(
                get: { viewModel.advancedDebugVisible },
                set: { viewModel.setAdvancedDebugVisible($0) }
            ))
            .toggleStyle(.checkbox)
            .font(CFTypography.caption)

            if !presentation.advancedDetails.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(presentation.advancedDetails, id: \.self) { detail in
                        Text(detail)
                            .font(CFTypography.caption)
                            .foregroundStyle(CFColors.textMuted)
                    }
                }
            }
        }
        .padding(CFSpacing.lg)
        .frame(width: 360, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .stroke(CFColors.separator, lineWidth: CFSeparators.width)
        )
        .cfShadow(.elevated)
    }

    private func nextEpisodeCard(_ prompt: PlayerNextEpisodePrompt) -> some View {
        VStack(alignment: .leading, spacing: CFSpacing.sm) {
            Text(t(.playerNextEpisodeTitle))
                .font(CFTypography.title)
                .foregroundStyle(CFColors.textPrimary)
            Text(prompt.title)
                .font(CFTypography.body)
                .foregroundStyle(CFColors.textSecondary)
            if !prompt.subtitle.isEmpty {
                Text(prompt.subtitle)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
            }
            if let seconds = viewModel.nextEpisodeCountdownSeconds {
                Text(L10n.format(.playerNextEpisodeCountdownFormat, language: languageSettingsStore.selectedLanguage, seconds))
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
                    .monospacedDigit()
            }
            HStack(spacing: CFSpacing.sm) {
                PrimaryButton(nextEpisodePrimaryTitle(for: prompt), systemImage: prompt.requiresManualReleaseSelection ? "list.bullet.rectangle" : "forward.end.fill") {
                    if let action = prompt.nextEpisodeAction {
                        onNextEpisode(action)
                    } else {
                        onExit()
                    }
                }
                SecondaryButton(t(.playerNextEpisodeDismiss), systemImage: "xmark") {
                    viewModel.cancelNextEpisodeCountdown()
                }
            }
        }
        .padding(CFSpacing.lg)
        .frame(width: 380, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .stroke(CFColors.focusRing.opacity(0.34), lineWidth: CFSeparators.width)
        )
        .cfShadow(.elevated)
    }

    private func nextEpisodePrimaryTitle(for prompt: PlayerNextEpisodePrompt) -> String {
        prompt.requiresManualReleaseSelection ? t(.playerNextEpisodeChooseRelease) : t(.playerNextEpisodeAction)
    }

    private func fallbackCard(_ suggestion: ReleaseFallbackSuggestion) -> some View {
        VStack(alignment: .leading, spacing: CFSpacing.sm) {
            Label(fallbackTitle(for: suggestion.reason), systemImage: "exclamationmark.triangle.fill")
                .font(CFTypography.title)
                .foregroundStyle(CFColors.textPrimary)

            Text(fallbackMessage(for: suggestion))
                .font(CFTypography.body)
                .foregroundStyle(CFColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let next = suggestion.nextBestRelease {
                PrimaryButton(t(.playerFallbackTryNext), systemImage: "arrow.triangle.2.circlepath") {
                    Task { await viewModel.tryNextBestRelease() }
                }
                .help(next.release.title)
            }
        }
        .padding(CFSpacing.lg)
        .frame(width: 360, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .stroke(CFColors.warning.opacity(0.35), lineWidth: CFSeparators.width)
        )
        .cfShadow(.elevated)
    }

    private var controls: some View {
        VStack(spacing: CFSpacing.md) {
            timelineControl

            HStack(spacing: CFSpacing.md) {
                Text(viewModel.elapsedLabel)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
                    .monospacedDigit()
                    .frame(width: 58, alignment: .leading)

                IconButton(systemImage: "gobackward.10", accessibilityLabel: t(.playerControlRewind)) {
                    Task { await viewModel.seekBackward() }
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                IconButton(systemImage: playPauseIcon, accessibilityLabel: t(.playerControlPlayPause)) {
                    Task { await viewModel.togglePlayPause() }
                }
                .keyboardShortcut(.space, modifiers: [])

                IconButton(systemImage: "goforward.10", accessibilityLabel: t(.playerControlForward)) {
                    Task { await viewModel.seekForward() }
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                IconButton(systemImage: viewModel.status.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", accessibilityLabel: t(.playerControlMute)) {
                    Task { await viewModel.toggleMuted() }
                }

                Slider(
                    value: Binding(
                        get: { viewModel.status.volume },
                        set: { value in Task { await viewModel.setVolume(value) } }
                    ),
                    in: 0...1
                )
                .frame(width: 120)
                .keyboardShortcut(.upArrow, modifiers: [])
                .accessibilityLabel(t(.playerControlVolume))
                .accessibilityValue("\(Int(viewModel.status.volume * 100))%")
                .help(t(.playerControlVolume))

                Menu(t(.playerControlAudio)) {
                    Text(viewModel.audioSelectionSummary)
                    audioBoostControls
                    if !viewModel.audioMenuTracks.isEmpty {
                        Divider()
                    }
                    ForEach(viewModel.audioMenuTracks) { track in
                        Button("\(track.isSelected ? "✓ " : "")\(track.languageLabel) · \(track.title) · \(track.qualityLabel)") {
                            Task { await viewModel.selectAudioTrack(id: track.id) }
                        }
                        .keyboardShortcut(track.languageLabel.lowercased().hasPrefix("r") ? "1" : "2", modifiers: [.command, .option])
                    }
                }
                .keyboardShortcut("a", modifiers: [])
                .help(t(.playerControlAudio))
                .accessibilityLabel(t(.playerControlAudio))

                Menu(t(.playerControlSubtitles)) {
                    Button(t(.playerControlSubtitlesOff)) {
                        Task { await viewModel.disableSubtitles() }
                    }
                    .keyboardShortcut("0", modifiers: [.command, .option])

                    Divider()
                    subtitleComfortControls

                    Section("Embedded") {
                        if viewModel.embeddedSubtitleTracks.isEmpty {
                            Text("No embedded subtitles")
                        } else {
                            ForEach(viewModel.embeddedSubtitleTracks) { track in
                                Button(subtitleMenuTitle(track)) {
                                    Task { await viewModel.selectSubtitleTrack(id: track.id) }
                                }
                            }
                        }
                    }

                    Section("Local") {
                        Button(t(.playerControlLoadLocalFile)) {
                            openLocalSubtitle()
                        }
                        Button("Reload local/cache") {
                            Task { await viewModel.reloadLocalSubtitles() }
                        }
                        ForEach(viewModel.localSubtitleTracks) { track in
                            Button(subtitleMenuTitle(track)) {
                                Task { await viewModel.selectSubtitleTrack(id: track.id) }
                            }
                        }
                    }

                    Section("Online") {
                        ForEach(viewModel.onlineSubtitleTracks) { track in
                            Button(subtitleMenuTitle(track)) {
                                Task { await viewModel.selectSubtitleTrack(id: track.id) }
                            }
                        }
                        ForEach(viewModel.onlineSubtitleResults) { result in
                            Button("Download \(result.languageCode.uppercased()) - \(result.title)") {
                                Task { await viewModel.downloadSubtitle(result) }
                            }
                        }
                    }

                    Section("Search more") {
                        Button(t(.playerControlFindOnline)) {
                            Task { await viewModel.findOnlineSubtitles() }
                        }
                    }
                }
                .keyboardShortcut("s", modifiers: [])
                .help(t(.playerControlSubtitles))
                .accessibilityLabel(t(.playerControlSubtitles))

                Menu(t(.playerControlSpeed)) {
                    ForEach(viewModel.speedChoices, id: \.self) { speed in
                        Button("\(speed, specifier: "%.2g")x") {
                            Task { await viewModel.setPlaybackSpeed(speed) }
                        }
                    }
                    Divider()
                    Button("Slower") {
                        Task { await viewModel.decreasePlaybackSpeed() }
                    }
                    .keyboardShortcut(",", modifiers: [])
                    Button("Faster") {
                        Task { await viewModel.increasePlaybackSpeed() }
                    }
                    .keyboardShortcut(".", modifiers: [])
                }
                .help(t(.playerControlSpeed))
                .accessibilityLabel(t(.playerControlSpeed))

                if !viewModel.chapters.isEmpty {
                    Menu("Chapters") {
                        ForEach(viewModel.chapters) { chapter in
                            Button("\(chapter.title) · \(timeLabel(chapter.startTime))") {
                                Task { await viewModel.seekToChapter(chapter) }
                            }
                        }
                    }
                    .keyboardShortcut("c", modifiers: [])
                    .help("Chapters")
                    .accessibilityLabel("Chapters")
                }

                Spacer()

                Text(viewModel.durationLabel)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
                    .monospacedDigit()
                    .frame(width: 58, alignment: .trailing)

                IconButton(systemImage: "pip", accessibilityLabel: t(.playerControlPictureInPicture)) {}
                    .disabled(true)

                IconButton(systemImage: viewModel.status.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", accessibilityLabel: t(.playerControlFullscreen)) {
                    Task { await viewModel.toggleFullscreen() }
                }
                .keyboardShortcut("f", modifiers: [])

                IconButton(systemImage: viewModel.dimBackgroundAroundVideo ? "circle.lefthalf.filled" : "circle", accessibilityLabel: "Dim background") {
                    Task { await viewModel.toggleDimBackground() }
                }
                .keyboardShortcut("d", modifiers: [.command])

            }
        }
        .padding(CFSpacing.lg)
        .cinematicChrome(in: RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous))
        .padding(.horizontal, CFSpacing.xl)
        .padding(.bottom, CFSpacing.lg)
    }

    private var timelineControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                if hasKnownTimelineDuration {
                    ZStack(alignment: .topLeading) {
                        Slider(
                            value: Binding(
                                get: { min(max(timelineScrubTime ?? viewModel.status.currentTime, 0), timelineUpperBound) },
                                set: { value in
                                    timelineScrubTime = value
                                    viewModel.requestTimelinePreview(at: value)
                                }
                            ),
                            in: 0...timelineUpperBound,
                            onEditingChanged: { editing in
                                isScrubbingTimeline = editing
                                if !editing, let timelineScrubTime {
                                    let target = timelineScrubTime
                                    self.timelineScrubTime = nil
                                    Task { await viewModel.seek(to: target) }
                                }
                            }
                        )
                        .accessibilityLabel(t(.playerControlTimeline))
                        .accessibilityValue("\(timelineDisplayLabel) / \(viewModel.durationLabel)")
                        .help("\(timelineDisplayLabel) / \(viewModel.durationLabel)")
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let width = max(1, proxy.size.width)
                                let clampedX = min(max(0, location.x), width)
                                timelineHoverX = clampedX
                                let time = Double(clampedX / width) * timelineUpperBound
                                viewModel.requestTimelinePreview(at: time)
                            case .ended:
                                if !isScrubbingTimeline {
                                    timelineHoverX = nil
                                    viewModel.hideTimelinePreview()
                                }
                            }
                        }

                        if let timelineHoverX, !viewModel.timelinePreview.isHidden {
                            timelinePreviewBubble
                                .offset(x: previewBubbleX(timelineHoverX, width: proxy.size.width), y: -94)
                                .transition(.opacity)
                        }
                    }
                } else {
                    unknownDurationTimelineRail
                }
            }
            .frame(height: 30)

            if !viewModel.chapters.isEmpty {
                HStack(spacing: 0) {
                    ForEach(viewModel.chapters) { chapter in
                        Button {
                            Task { await viewModel.seekToChapter(chapter) }
                        } label: {
                            Rectangle()
                                .fill(CFColors.textSecondary.opacity(0.6))
                                .frame(width: 2, height: 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help("\(chapter.title) · \(timeLabel(chapter.startTime))")
                        .accessibilityLabel("Chapter \(chapter.title)")
                    }
                }
                .frame(height: 8)
            }
        }
    }

    private var timelinePreviewBubble: some View {
        VStack(spacing: 6) {
            Group {
                if let data = viewModel.timelinePreview.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(Color.black.opacity(0.45))
                        if viewModel.timelinePreview.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "film")
                                .foregroundStyle(CFColors.textSecondary)
                        }
                    }
                }
            }
            .frame(width: 160, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: CFRadius.control, style: .continuous))

            Text(viewModel.timelinePreview.isUnavailable ? viewModel.timelinePreview.message : viewModel.timelinePreview.timeLabel)
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textPrimary)
                .lineLimit(1)
                .monospacedDigit()
        }
        .padding(6)
        .frame(width: 172)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .stroke(CFColors.separator.opacity(0.5), lineWidth: CFSeparators.width)
        )
        .allowsHitTesting(false)
    }

    private func previewBubbleX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        let bubbleWidth: CGFloat = 172
        return min(max(0, x - bubbleWidth / 2), max(0, width - bubbleWidth))
    }

    private var audioBoostControls: some View {
        Group {
            Button("Boost -") {
                Task { await viewModel.decreaseAudioBoost() }
            }
            .keyboardShortcut("-", modifiers: [])
            Button("Boost \(viewModel.status.audioBoost, specifier: "%.2g")x") {
                Task { await viewModel.setAudioBoost(viewModel.status.audioBoost == 1 ? 1.5 : 1) }
            }
            Button("Boost +") {
                Task { await viewModel.increaseAudioBoost() }
            }
            .keyboardShortcut("=", modifiers: [])
        }
    }

    private var subtitleComfortControls: some View {
        Group {
            Menu("Style") {
                ForEach(SubtitleVisualStyle.allCases) { style in
                    Button(style.title) {
                        Task { await viewModel.setSubtitleStyle(style) }
                    }
                }
            }
            Menu("Size") {
                ForEach([32.0, 42.0, 52.0, 64.0], id: \.self) { size in
                    Button("\(Int(size))") {
                        Task { await viewModel.setSubtitleFontSize(size) }
                    }
                }
            }
            Button("Delay -0.5s") {
                Task { await viewModel.adjustSubtitleDelay(by: -0.5) }
            }
            .keyboardShortcut("[", modifiers: [])
            Button("Reset delay") {
                Task { await viewModel.resetSubtitleDelay() }
            }
            Button("Delay +0.5s") {
                Task { await viewModel.adjustSubtitleDelay(by: 0.5) }
            }
            .keyboardShortcut("]", modifiers: [])
        }
    }

    private var timelineUpperBound: Double {
        max(viewModel.status.duration ?? 1, 1)
    }

    private var hasKnownTimelineDuration: Bool {
        guard let duration = viewModel.status.duration else { return false }
        return duration > 0
    }

    private var unknownDurationTimelineRail: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(CFColors.separator.opacity(0.55))
            .frame(height: 6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityLabel(t(.playerControlTimeline))
            .accessibilityValue("\(timelineDisplayLabel) / \(viewModel.durationLabel)")
            .help("\(timelineDisplayLabel) / \(viewModel.durationLabel)")
    }

    private var timelineDisplayLabel: String {
        timeLabel(timelineScrubTime ?? viewModel.status.currentTime)
    }

    private var playPauseIcon: String {
        viewModel.status.state == .playing ? "pause.fill" : "play.fill"
    }

    private func timeLabel(_ value: Double) -> String {
        let totalSeconds = max(0, Int(value.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func subtitleMenuTitle(_ track: SubtitleTrack) -> String {
        let forced = track.isForced ? " · Forced" : ""
        return "\(track.languageCode.uppercased()) · \(track.displayName)\(forced)"
    }

    private var sourceInfo: String {
        [
            viewModel.status.media?.selectionContext?.episodeLabel,
            viewModel.status.qualityLabel,
            viewModel.status.sourceName,
            bufferingText
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var bufferingText: String? {
        switch viewModel.status.bufferingState {
        case .idle:
            nil
        case .ready:
            t(.playerReady)
        case .buffering(let progress):
            L10n.format(.playerBufferingFormat, language: languageSettingsStore.selectedLanguage, Int(progress * 100))
        }
    }

    private func fallbackTitle(for reason: ReleaseFallbackReason) -> String {
        switch reason {
        case .failedToStart:
            t(.playerFallbackFailedToStartTitle)
        case .noSeeders:
            t(.playerFallbackNoSeedersTitle)
        case .stalled:
            t(.playerFallbackStalledTitle)
        case .unsupportedFile:
            t(.playerFallbackUnsupportedTitle)
        case .missingMediaFile:
            t(.playerFallbackMissingMediaTitle)
        }
    }

    private func fallbackMessage(for suggestion: ReleaseFallbackSuggestion) -> String {
        guard let next = suggestion.nextBestRelease else {
            return t(.playerFallbackNoAlternativeMessage)
        }
        return L10n.format(
            .playerFallbackAlternativeFormat,
            language: languageSettingsStore.selectedLanguage,
            next.release.title,
            next.release.qualityLabel,
            next.release.seeders
        )
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: languageSettingsStore.selectedLanguage)
    }

    private func openLocalSubtitle() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["srt", "ass"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await viewModel.loadLocalSubtitle(url: url) }
        }
    }
}

private struct AVPlayerRenderView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

private struct PlayerKeyboardInputView: NSViewRepresentable {
    let onShortcut: (PlayerKeyboardShortcut) -> Void

    func makeNSView(context: Context) -> KeyboardCaptureView {
        let view = KeyboardCaptureView()
        view.onShortcut = onShortcut
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyboardCaptureView, context: Context) {
        nsView.onShortcut = onShortcut
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class KeyboardCaptureView: NSView {
        var onShortcut: ((PlayerKeyboardShortcut) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard let shortcut = Self.shortcut(from: event) else {
                super.keyDown(with: event)
                return
            }
            onShortcut?(shortcut)
        }

        private static func shortcut(from event: NSEvent) -> PlayerKeyboardShortcut? {
            let shift = event.modifierFlags.contains(.shift)
            switch event.keyCode {
            case 49:
                return .space
            case 123:
                return shift ? .shiftLeft : .left
            case 124:
                return shift ? .shiftRight : .right
            case 125:
                return .down
            case 126:
                return .up
            case 53:
                return .escape
            default:
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "m":
                    return .mute
                case "f":
                    return .fullscreen
                case "s":
                    return .subtitles
                case "a":
                    return .audio
                case ",":
                    return .speedDown
                case ".":
                    return .speedUp
                case "[":
                    return .subtitleDelayDown
                case "]":
                    return .subtitleDelayUp
                case "-":
                    return .audioBoostDown
                case "=":
                    return .audioBoostUp
                default:
                    return nil
                }
            }
        }
    }
}

private struct PlayerMouseActivityView: NSViewRepresentable {
    let onActivity: () -> Void

    func makeNSView(context: Context) -> MouseActivityCaptureView {
        let view = MouseActivityCaptureView()
        view.onActivity = onActivity
        return view
    }

    func updateNSView(_ nsView: MouseActivityCaptureView, context: Context) {
        nsView.onActivity = onActivity
    }

    final class MouseActivityCaptureView: NSView {
        var onActivity: (() -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
                    owner: self,
                    userInfo: nil
                )
            )
        }

        override func mouseMoved(with event: NSEvent) {
            onActivity?()
            super.mouseMoved(with: event)
        }

        override func mouseEntered(with event: NSEvent) {
            onActivity?()
            super.mouseEntered(with: event)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
