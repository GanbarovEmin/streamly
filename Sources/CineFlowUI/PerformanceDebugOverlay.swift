import CineFlowCore
import CineFlowDesignSystem
import SwiftUI

public struct PerformanceDebugOverlay: View {
    @ObservedObject private var imagePipeline: CineFlowImagePipeline
    private let environment: AppEnvironment

    @State private var cacheSizeLabel = "Cache --"
    @State private var playbackStatusLabel = "Playback idle"

    public init(imagePipeline: CineFlowImagePipeline, environment: AppEnvironment) {
        self.imagePipeline = imagePipeline
        self.environment = environment
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Performance")
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textPrimary)
            metric("cache", cacheSizeLabel)
            metric("images", "\(imagePipeline.loadedImageCount) loaded")
            metric("requests", "\(imagePipeline.activeRequestCount) active")
            metric("playback", playbackStatusLabel)
        }
        .padding(CFSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .fill(CFColors.backgroundPrimary.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
        .padding(CFSpacing.lg)
        .allowsHitTesting(false)
        .task {
            await poll()
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack(spacing: CFSpacing.sm) {
            Text(title)
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textMuted)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textSecondary)
                .monospacedDigit()
        }
    }

    private func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func refresh() async {
        if let bytes = try? await environment.imageCacheService?.cacheSizeBytes() {
            cacheSizeLabel = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        } else {
            cacheSizeLabel = "Unavailable"
        }

        let status = await environment.playbackService.currentStatus
        playbackStatusLabel = label(for: status)
    }

    private func label(for status: PlaybackStatus) -> String {
        switch status.state {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .playing:
            return "playing \(Int(status.currentTime))s"
        case .paused:
            return "paused \(Int(status.currentTime))s"
        case .stopped:
            return "stopped"
        case .failed:
            return "failed"
        }
    }
}
