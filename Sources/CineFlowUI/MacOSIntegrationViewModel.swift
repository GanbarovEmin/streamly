import AppKit
import CineFlowCore
import Foundation
import UniformTypeIdentifiers

@MainActor
public final class MacOSIntegrationViewModel: ObservableObject {
    @Published public private(set) var lastImportedSession: TorrentSession?
    @Published public private(set) var permissionErrorMessage: String?
    @Published public private(set) var isDropTargeted = false

    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public func handleOpenURL(_ url: URL) async {
        if url.scheme?.lowercased() == "magnet" {
            await handleMagnet(url.absoluteString)
            return
        }

        guard url.isFileURL, url.pathExtension.lowercased() == "torrent" else {
            permissionErrorMessage = "Streamly can open only .torrent files or magnet links."
            return
        }

        await handleTorrentFile(url)
    }

    public func handleDroppedText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("magnet:?") else {
            permissionErrorMessage = "Dropped text is not a magnet link."
            return
        }
        await handleMagnet(trimmed)
    }

    public func handleDroppedFile(_ url: URL) async {
        await handleOpenURL(url)
    }

    public func handleDropProviders(_ providers: [NSItemProvider]) -> Bool {
        isDropTargeted = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                    guard let self, let url = Self.url(fromProviderItem: item) else { return }
                    Task { @MainActor in await self.handleDroppedFile(url) }
                }
                return true
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                    guard let self, let text = Self.text(fromProviderItem: item) else { return }
                    Task { @MainActor in await self.handleDroppedText(text) }
                }
                return true
            }
        }

        permissionErrorMessage = "Drop a .torrent file or magnet link."
        return false
    }

    public func setDropTargeted(_ targeted: Bool) {
        isDropTargeted = targeted
    }

    public func openTorrentPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.torrent]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a .torrent file to open in Streamly."

        if panel.runModal() == .OK, let url = panel.url {
            Task { await handleTorrentFile(url) }
        }
    }

    public func promptForMagnetLink() {
        let alert = NSAlert()
        alert.messageText = "Open Magnet Link"
        alert.informativeText = "Paste a magnet:? link to add it to Streamly."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 480, height: 24))
        input.placeholderString = "magnet:?xt=urn:btih:..."
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            Task { await handleDroppedText(input.stringValue) }
        }
    }

    public func exportDiagnosticsFromMenu() async {
        _ = await environment.diagnosticsService.exportDiagnostics()
    }

    public func toggleFullscreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    private func handleMagnet(_ magnet: String) async {
        do {
            lastImportedSession = try await environment.torrentEngine.addMagnet(uri: magnet)
            permissionErrorMessage = nil
        } catch {
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .torrent)
            await environment.diagnosticsService.log(cineFlowError, operation: "addMagnet")
            permissionErrorMessage = message(for: cineFlowError, original: error)
        }
    }

    private func handleTorrentFile(_ url: URL) async {
        do {
            lastImportedSession = try await environment.torrentEngine.addTorrentFile(url: url)
            permissionErrorMessage = nil
        } catch {
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .torrent)
            await environment.diagnosticsService.log(cineFlowError, operation: "addTorrentFile", metadata: ["file": url.lastPathComponent])
            permissionErrorMessage = message(for: cineFlowError, original: error)
        }
    }

    private func message(for error: CineFlowError, original: Error) -> String {
        if let cocoaError = original as? CocoaError, cocoaError.code == .fileReadNoPermission || cocoaError.code == .fileWriteNoPermission {
            return "Streamly could not access this file or folder. Choose a readable location in Settings or grant macOS permission."
        }

        if case TorrentEngineError.invalidTorrentFile = original {
            return "The selected .torrent file is invalid."
        }

        if case TorrentEngineError.invalidMagnetURI = original {
            return "The magnet link is invalid."
        }

        return error.userMessage
    }

    private nonisolated static func url(fromProviderItem item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
            return URL(string: string)
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

    private nonisolated static func text(fromProviderItem item: NSSecureCoding?) -> String? {
        if let string = item as? String {
            return string
        }
        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}

private extension UTType {
    static var torrent: UTType {
        UTType(filenameExtension: "torrent") ?? .data
    }
}
