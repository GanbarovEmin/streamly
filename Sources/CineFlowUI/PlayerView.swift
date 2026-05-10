import CineFlowCore
import CineFlowDesignSystem
import CineFlowPlayback
import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct PlayerView: View {
    @StateObject private var viewModel: PlayerViewModel
    private let onExit: () -> Void

    public init(viewModel: PlayerViewModel, onExit: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onExit = onExit
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            MPVRenderView()
                .overlay(renderOverlay)
                .ignoresSafeArea()

            if viewModel.controlsAreVisible {
                controls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(CFColors.backgroundPrimary)
        .onHover { hovering in
            hovering ? viewModel.showControls() : viewModel.hideControls()
        }
        .task {
            await viewModel.start()
        }
        .onDisappear {
            Task { await viewModel.saveProgressOnClose() }
        }
        .focusable()
        .keyboardShortcut(.space, modifiers: [])
    }

    private var renderOverlay: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.status.media?.title ?? "Player")
                        .font(CFTypography.title)
                        .foregroundStyle(CFColors.textPrimary)

                    Text(sourceInfo)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textSecondary)
                }

                Spacer()

                if let error = viewModel.errorMessage {
                    ErrorState(title: "Playback", message: error)
                }
            }
            .padding(28)

            Spacer()
        }
    }

    private var controls: some View {
        VStack(spacing: CFSpacing.md) {
            ProgressBar(value: viewModel.status.progressFraction)
                .frame(height: 6)
                .padding(.horizontal, 4)

            HStack(spacing: CFSpacing.md) {
                Text(viewModel.elapsedLabel)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
                    .monospacedDigit()
                    .frame(width: 58, alignment: .leading)

                IconButton(systemImage: "gobackward.10", accessibilityLabel: "Rewind") {
                    Task { await viewModel.seekBackward() }
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                IconButton(systemImage: playPauseIcon, accessibilityLabel: "Play or pause") {
                    Task { await viewModel.togglePlayPause() }
                }
                .keyboardShortcut(.space, modifiers: [])

                IconButton(systemImage: "goforward.10", accessibilityLabel: "Forward") {
                    Task { await viewModel.seekForward() }
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                IconButton(systemImage: viewModel.status.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", accessibilityLabel: "Mute") {
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

                Menu("Audio") {
                    ForEach(viewModel.audioTracks) { track in
                        Button(track.displayName) {
                            Task { await viewModel.selectAudioTrack(id: track.id) }
                        }
                    }
                }
                .keyboardShortcut("a", modifiers: [])

                Menu("Subtitles") {
                    Button("Off") {
                        Task { await viewModel.disableSubtitles() }
                    }
                    Button("Find Online") {
                        Task { await viewModel.findOnlineSubtitles() }
                    }
                    Button("Load Local File") {
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

                Menu("Speed") {
                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button("\(speed, specifier: "%.2g")x") {
                            Task { await viewModel.setPlaybackSpeed(speed) }
                        }
                    }
                }

                Spacer()

                Text(viewModel.durationLabel)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
                    .monospacedDigit()
                    .frame(width: 58, alignment: .trailing)

                IconButton(systemImage: "pip", accessibilityLabel: "Picture in picture") {}
                    .disabled(true)

                IconButton(systemImage: viewModel.status.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", accessibilityLabel: "Fullscreen") {
                    Task { await viewModel.toggleFullscreen() }
                }
                .keyboardShortcut("f", modifiers: [])

                IconButton(systemImage: "xmark", accessibilityLabel: "Exit") {
                    Task { await viewModel.stop() }
                    onExit()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(CFSpacing.lg)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous)
                .fill(CFColors.backgroundSecondary.opacity(0.68))
        )
        .clipShape(RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous)
                .stroke(CFColors.separator, lineWidth: CFSeparators.width)
        )
        .cfShadow(.elevated)
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
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
            "Ready"
        case .buffering(let progress):
            "Buffering \(Int(progress * 100))%"
        }
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
