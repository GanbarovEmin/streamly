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
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore
    @Environment(\.cfReduceMotion) private var reduceMotion
    private let onExit: () -> Void

    public init(viewModel: PlayerViewModel, onExit: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onExit = onExit
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            playerRenderSurface
                .overlay(renderOverlay)
                .overlay(keyboardInput)
                .ignoresSafeArea()

            controls
                .opacity(viewModel.controlsAreVisible ? 1 : 0)
                .offset(y: viewModel.controlsAreVisible ? 0 : 18)
                .allowsHitTesting(viewModel.controlsAreVisible)
                .cfAnimation(CFMotion.standard, value: viewModel.controlsAreVisible, reduceMotion: reduceMotion)
        }
        .background(CFColors.backgroundPrimary)
        .onHover { hovering in
            hovering ? viewModel.showControlsTemporarily() : viewModel.hideControls()
        }
        .onTapGesture {
            viewModel.showControlsTemporarily()
        }
        .task {
            await viewModel.start()
            viewModel.showControlsTemporarily()
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
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.status.media?.title ?? t(.playerTitleFallback))
                        .font(CFTypography.title)
                        .foregroundStyle(CFColors.textPrimary)

                    Text(sourceInfo)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textSecondary)
                }

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
        return VStack(alignment: .leading, spacing: CFSpacing.sm) {
            HStack(spacing: CFSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text(t(.playerBufferingTitle))
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
                    .monospacedDigit()
            }

            ProgressBar(value: progress)
                .frame(height: 5)

            Text(L10n.format(.playerBufferingMessageFormat, language: languageSettingsStore.selectedLanguage, Int(progress * 100)))
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textSecondary)

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
            HStack(spacing: CFSpacing.sm) {
                PrimaryButton(t(.playerNextEpisodeAction), systemImage: "forward.end.fill") {
                    onExit()
                }
                SecondaryButton(t(.playerNextEpisodeDismiss), systemImage: "xmark") {
                    viewModel.dismissNextEpisodePrompt()
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
            Slider(
                value: Binding(
                    get: { viewModel.status.currentTime },
                    set: { value in
                        Task { await viewModel.seek(to: value) }
                    }
                ),
                in: 0...timelineUpperBound
            )
            .accessibilityLabel(t(.playerControlTimeline))
            .accessibilityValue("\(viewModel.elapsedLabel) / \(viewModel.durationLabel)")
            .help("\(viewModel.elapsedLabel) / \(viewModel.durationLabel)")

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
                    ForEach(viewModel.audioTracks) { track in
                        Button(track.displayName) {
                            Task { await viewModel.selectAudioTrack(id: track.id) }
                        }
                    }
                }
                .keyboardShortcut("a", modifiers: [])
                .help(t(.playerControlAudio))
                .accessibilityLabel(t(.playerControlAudio))

                Menu(t(.playerControlSubtitles)) {
                    Button(t(.playerControlSubtitlesOff)) {
                        Task { await viewModel.disableSubtitles() }
                    }
                    Button(t(.playerControlFindOnline)) {
                        Task { await viewModel.findOnlineSubtitles() }
                    }
                    Button(t(.playerControlLoadLocalFile)) {
                        openLocalSubtitle()
                    }
                    ForEach(viewModel.subtitleTracks) { track in
                        Button(track.displayName) {
                            Task { await viewModel.selectSubtitleTrack(id: track.id) }
                        }
                    }
                    if !viewModel.onlineSubtitleResults.isEmpty {
                        Divider()
                        ForEach(viewModel.onlineSubtitleResults) { result in
                            Button("Download \(result.languageCode.uppercased()) - \(result.title)") {
                                Task { await viewModel.downloadSubtitle(result) }
                            }
                        }
                    }
                }
                .keyboardShortcut("s", modifiers: [])
                .help(t(.playerControlSubtitles))
                .accessibilityLabel(t(.playerControlSubtitles))

                Menu(t(.playerControlSpeed)) {
                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button("\(speed, specifier: "%.2g")x") {
                            Task { await viewModel.setPlaybackSpeed(speed) }
                        }
                    }
                }
                .help(t(.playerControlSpeed))
                .accessibilityLabel(t(.playerControlSpeed))

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

                IconButton(systemImage: "xmark", accessibilityLabel: t(.playerControlExit)) {
                    Task { await viewModel.stop() }
                    onExit()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(CFSpacing.lg)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous))
        .background(RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous).fill(CFColors.railFill))
        .clipShape(RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous)
                .stroke(CFColors.separator, lineWidth: CFSeparators.width)
        )
        .cfShadow(.elevated)
        .padding(.horizontal, CFSpacing.xl)
        .padding(.bottom, CFSpacing.lg)
    }

    private var timelineUpperBound: Double {
        max(viewModel.status.duration ?? 0, viewModel.status.currentTime + 1, 1)
    }

    private var playPauseIcon: String {
        viewModel.status.state == .playing ? "pause.fill" : "play.fill"
    }

    private var sourceInfo: String {
        [
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
                default:
                    return nil
                }
            }
        }
    }
}
