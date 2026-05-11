import CineFlowCore
import Darwin
import Foundation

public struct NativeLibtorrentEngineHandle: @unchecked Sendable {
    public let rawValue: OpaquePointer

    public init(rawValue: OpaquePointer) {
        self.rawValue = rawValue
    }
}

public protocol NativeLibtorrentABI: Sendable {
    func createEngine(storagePath: String) throws -> NativeLibtorrentEngineHandle
    func destroyEngine(_ engine: NativeLibtorrentEngineHandle)
    func addMagnet(engine: NativeLibtorrentEngineHandle, uri: String, storagePath: String) throws -> String
    func addTorrentFile(engine: NativeLibtorrentEngineHandle, torrentPath: String, storagePath: String) throws -> String
    func start(engine: NativeLibtorrentEngineHandle, handle: String) throws
    func pause(engine: NativeLibtorrentEngineHandle, handle: String) throws
    func resume(engine: NativeLibtorrentEngineHandle, handle: String) throws
    func stop(engine: NativeLibtorrentEngineHandle, handle: String) throws
    func remove(engine: NativeLibtorrentEngineHandle, handle: String, deleteFiles: Bool) throws
    func statusJSON(engine: NativeLibtorrentEngineHandle, handle: String) throws -> String
    func filesJSON(engine: NativeLibtorrentEngineHandle, handle: String) throws -> String
    func selectFile(engine: NativeLibtorrentEngineHandle, handle: String, fileId: String) throws
    func setSequentialDownload(engine: NativeLibtorrentEngineHandle, handle: String, enabled: Bool) throws
    func setDownloadPriority(engine: NativeLibtorrentEngineHandle, handle: String, fileId: String, priority: TorrentFilePriority) throws
    func setBandwidthLimits(engine: NativeLibtorrentEngineHandle, handle: String, limits: TorrentBandwidthLimits) throws
    func streamingURL(engine: NativeLibtorrentEngineHandle, handle: String) throws -> URL
}

public actor NativeLibtorrentBridge: LibtorrentBridgeProtocol {
    private let abi: any NativeLibtorrentABI
    private let engineStorageURL: URL
    private var engine: NativeLibtorrentEngineHandle?

    public init(
        abi: any NativeLibtorrentABI = SystemNativeLibtorrentABI(),
        engineStorageURL: URL = TorrentCacheLocation.defaultStorageURL()
    ) {
        self.abi = abi
        self.engineStorageURL = engineStorageURL
    }

    deinit {
        if let engine {
            abi.destroyEngine(engine)
        }
    }

    public func addMagnet(uri: String, storageURL: URL) async throws -> String {
        try abi.addMagnet(
            engine: try engineHandle(),
            uri: uri,
            storagePath: storageURL.path
        )
    }

    public func addTorrentFile(url: URL, storageURL: URL) async throws -> String {
        try abi.addTorrentFile(
            engine: try engineHandle(),
            torrentPath: url.path,
            storagePath: storageURL.path
        )
    }

    public func start(handle: String) async throws {
        try abi.start(engine: try engineHandle(), handle: handle)
    }

    public func pause(handle: String) async throws {
        try abi.pause(engine: try engineHandle(), handle: handle)
    }

    public func resume(handle: String) async throws {
        try abi.resume(engine: try engineHandle(), handle: handle)
    }

    public func stop(handle: String) async throws {
        try abi.stop(engine: try engineHandle(), handle: handle)
    }

    public func remove(handle: String, deleteFiles: Bool) async throws {
        try abi.remove(engine: try engineHandle(), handle: handle, deleteFiles: deleteFiles)
    }

    public func status(handle: String) async throws -> TorrentStatus {
        let json = try abi.statusJSON(engine: try engineHandle(), handle: handle)
        let dto = try NativeTorrentStatusDTO.decode(json)
        return try dto.status(defaultSessionId: handle)
    }

    public func files(handle: String) async throws -> [TorrentFile] {
        let json = try abi.filesJSON(engine: try engineHandle(), handle: handle)
        return try NativeTorrentFileDTO.decode(json).map(\.file)
    }

    public func selectFile(handle: String, fileId: String) async throws {
        do {
            try abi.selectFile(engine: try engineHandle(), handle: handle, fileId: fileId)
        } catch let error as TorrentEngineError where error == .libtorrentUnavailable {
            throw error
        } catch let error as TorrentEngineError {
            if case .fileNotFound = error {
                throw error
            }
            throw TorrentEngineError.fileNotFound(sessionId: handle, fileId: fileId)
        } catch {
            throw TorrentEngineError.fileNotFound(sessionId: handle, fileId: fileId)
        }
    }

    public func setSequentialDownload(handle: String, enabled: Bool) async throws {
        try abi.setSequentialDownload(engine: try engineHandle(), handle: handle, enabled: enabled)
    }

    public func setDownloadPriority(handle: String, fileId: String, priority: TorrentFilePriority) async throws {
        try abi.setDownloadPriority(engine: try engineHandle(), handle: handle, fileId: fileId, priority: priority)
    }

    public func setBandwidthLimits(handle: String, limits: TorrentBandwidthLimits) async throws {
        try abi.setBandwidthLimits(engine: try engineHandle(), handle: handle, limits: limits)
    }

    public func streamingURL(handle: String) async throws -> URL {
        do {
            return try abi.streamingURL(engine: try engineHandle(), handle: handle)
        } catch let error as TorrentEngineError where error == .libtorrentUnavailable {
            throw error
        } catch {
            throw TorrentEngineError.streamingURLUnavailable(sessionId: handle)
        }
    }

    private func engineHandle() throws -> NativeLibtorrentEngineHandle {
        if let engine {
            return engine
        }

        try FileManager.default.createDirectory(at: engineStorageURL, withIntermediateDirectories: true)
        let created = try abi.createEngine(storagePath: engineStorageURL.path)
        engine = created
        return created
    }
}

public final class SystemNativeLibtorrentABI: NativeLibtorrentABI, @unchecked Sendable {
    private typealias CreateEngineFunction = @convention(c) (
        UnsafePointer<CChar>,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> OpaquePointer?
    private typealias DestroyEngineFunction = @convention(c) (OpaquePointer?) -> Void
    private typealias StringResultFunction = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>,
        UnsafePointer<CChar>,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> UnsafeMutablePointer<CChar>?
    private typealias ControlFunction = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias RemoveFunction = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>,
        Bool,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias JSONFunction = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> UnsafeMutablePointer<CChar>?
    private typealias SelectFileFunction = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>,
        UnsafePointer<CChar>,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias SetSequentialFunction = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>,
        Bool,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias SetPriorityFunction = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>,
        UnsafePointer<CChar>,
        Int32,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias SetBandwidthLimitsFunction = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>,
        Int64,
        Int64,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias StringFreeFunction = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    private let library: UnsafeMutableRawPointer?
    private let createEngineFunction: CreateEngineFunction?
    private let destroyEngineFunction: DestroyEngineFunction?
    private let addMagnetFunction: StringResultFunction?
    private let addTorrentFileFunction: StringResultFunction?
    private let startFunction: ControlFunction?
    private let pauseFunction: ControlFunction?
    private let resumeFunction: ControlFunction?
    private let stopFunction: ControlFunction?
    private let removeFunction: RemoveFunction?
    private let statusJSONFunction: JSONFunction?
    private let filesJSONFunction: JSONFunction?
    private let selectFileFunction: SelectFileFunction?
    private let setSequentialFunction: SetSequentialFunction?
    private let setPriorityFunction: SetPriorityFunction?
    private let setBandwidthLimitsFunction: SetBandwidthLimitsFunction?
    private let streamingURLFunction: JSONFunction?
    private let stringFreeFunction: StringFreeFunction?

    public init() {
        library = Self.openLibrary()
        createEngineFunction = Self.symbol("cf_libtorrent_engine_create", library: library)
        destroyEngineFunction = Self.symbol("cf_libtorrent_engine_destroy", library: library)
        addMagnetFunction = Self.symbol("cf_libtorrent_add_magnet", library: library)
        addTorrentFileFunction = Self.symbol("cf_libtorrent_add_torrent_file", library: library)
        startFunction = Self.symbol("cf_libtorrent_start", library: library)
        pauseFunction = Self.symbol("cf_libtorrent_pause", library: library)
        resumeFunction = Self.symbol("cf_libtorrent_resume", library: library)
        stopFunction = Self.symbol("cf_libtorrent_stop", library: library)
        removeFunction = Self.symbol("cf_libtorrent_remove", library: library)
        statusJSONFunction = Self.symbol("cf_libtorrent_status_json", library: library)
        filesJSONFunction = Self.symbol("cf_libtorrent_files_json", library: library)
        selectFileFunction = Self.symbol("cf_libtorrent_select_file", library: library)
        setSequentialFunction = Self.symbol("cf_libtorrent_set_sequential", library: library)
        setPriorityFunction = Self.symbol("cf_libtorrent_set_priority", library: library)
        setBandwidthLimitsFunction = Self.symbol("cf_libtorrent_set_bandwidth_limits", library: library)
        streamingURLFunction = Self.symbol("cf_libtorrent_streaming_url", library: library)
        stringFreeFunction = Self.symbol("cf_libtorrent_string_free", library: library)
    }

    deinit {
        if let library {
            dlclose(library)
        }
    }

    public func createEngine(storagePath: String) throws -> NativeLibtorrentEngineHandle {
        guard let createEngineFunction else {
            throw TorrentEngineError.libtorrentUnavailable
        }

        var errorPointer: UnsafeMutablePointer<CChar>?
        guard let rawHandle = storagePath.withCString({
            createEngineFunction($0, &errorPointer)
        }) else {
            throw nativeError(errorPointer)
        }
        return NativeLibtorrentEngineHandle(rawValue: rawHandle)
    }

    public func destroyEngine(_ engine: NativeLibtorrentEngineHandle) {
        destroyEngineFunction?(engine.rawValue)
    }

    public func addMagnet(engine: NativeLibtorrentEngineHandle, uri: String, storagePath: String) throws -> String {
        try callStringResult(addMagnetFunction, engine: engine, first: uri, second: storagePath)
    }

    public func addTorrentFile(engine: NativeLibtorrentEngineHandle, torrentPath: String, storagePath: String) throws -> String {
        try callStringResult(addTorrentFileFunction, engine: engine, first: torrentPath, second: storagePath)
    }

    public func start(engine: NativeLibtorrentEngineHandle, handle: String) throws {
        try callControl(startFunction, engine: engine, handle: handle)
    }

    public func pause(engine: NativeLibtorrentEngineHandle, handle: String) throws {
        try callControl(pauseFunction, engine: engine, handle: handle)
    }

    public func resume(engine: NativeLibtorrentEngineHandle, handle: String) throws {
        try callControl(resumeFunction, engine: engine, handle: handle)
    }

    public func stop(engine: NativeLibtorrentEngineHandle, handle: String) throws {
        try callControl(stopFunction, engine: engine, handle: handle)
    }

    public func remove(engine: NativeLibtorrentEngineHandle, handle: String, deleteFiles: Bool) throws {
        guard let removeFunction else {
            throw TorrentEngineError.libtorrentUnavailable
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = handle.withCString {
            removeFunction(engine.rawValue, $0, deleteFiles, &errorPointer)
        }
        try validateResult(result, errorPointer: errorPointer)
    }

    public func statusJSON(engine: NativeLibtorrentEngineHandle, handle: String) throws -> String {
        try callJSON(statusJSONFunction, engine: engine, handle: handle)
    }

    public func filesJSON(engine: NativeLibtorrentEngineHandle, handle: String) throws -> String {
        try callJSON(filesJSONFunction, engine: engine, handle: handle)
    }

    public func selectFile(engine: NativeLibtorrentEngineHandle, handle: String, fileId: String) throws {
        guard let selectFileFunction else {
            throw TorrentEngineError.libtorrentUnavailable
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = handle.withCString { handlePointer in
            fileId.withCString { filePointer in
                selectFileFunction(engine.rawValue, handlePointer, filePointer, &errorPointer)
            }
        }
        try validateResult(result, errorPointer: errorPointer)
    }

    public func setSequentialDownload(engine: NativeLibtorrentEngineHandle, handle: String, enabled: Bool) throws {
        guard let setSequentialFunction else {
            throw TorrentEngineError.libtorrentUnavailable
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = handle.withCString {
            setSequentialFunction(engine.rawValue, $0, enabled, &errorPointer)
        }
        try validateResult(result, errorPointer: errorPointer)
    }

    public func setDownloadPriority(engine: NativeLibtorrentEngineHandle, handle: String, fileId: String, priority: TorrentFilePriority) throws {
        guard let setPriorityFunction else {
            throw TorrentEngineError.libtorrentUnavailable
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = handle.withCString { handlePointer in
            fileId.withCString { filePointer in
                setPriorityFunction(engine.rawValue, handlePointer, filePointer, Int32(priority.rawValue), &errorPointer)
            }
        }
        try validateResult(result, errorPointer: errorPointer)
    }

    public func setBandwidthLimits(engine: NativeLibtorrentEngineHandle, handle: String, limits: TorrentBandwidthLimits) throws {
        guard let setBandwidthLimitsFunction else {
            return
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let downloadLimit = limits.downloadBytesPerSecond ?? -1
        let uploadLimit = limits.uploadBytesPerSecond ?? -1
        let result = handle.withCString {
            setBandwidthLimitsFunction(engine.rawValue, $0, downloadLimit, uploadLimit, &errorPointer)
        }
        try validateResult(result, errorPointer: errorPointer)
    }

    public func streamingURL(engine: NativeLibtorrentEngineHandle, handle: String) throws -> URL {
        let value = try callJSON(streamingURLFunction, engine: engine, handle: handle)
        guard let url = URL(string: value) else {
            throw TorrentEngineError.streamingURLUnavailable(sessionId: handle)
        }
        return url
    }

    private func callStringResult(
        _ function: StringResultFunction?,
        engine: NativeLibtorrentEngineHandle,
        first: String,
        second: String
    ) throws -> String {
        guard let function else {
            throw TorrentEngineError.libtorrentUnavailable
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let valuePointer = first.withCString { firstPointer in
            second.withCString { secondPointer in
                function(engine.rawValue, firstPointer, secondPointer, &errorPointer)
            }
        }
        return try string(from: valuePointer, errorPointer: errorPointer)
    }

    private func callControl(
        _ function: ControlFunction?,
        engine: NativeLibtorrentEngineHandle,
        handle: String
    ) throws {
        guard let function else {
            throw TorrentEngineError.libtorrentUnavailable
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = handle.withCString {
            function(engine.rawValue, $0, &errorPointer)
        }
        try validateResult(result, errorPointer: errorPointer)
    }

    private func callJSON(
        _ function: JSONFunction?,
        engine: NativeLibtorrentEngineHandle,
        handle: String
    ) throws -> String {
        guard let function else {
            throw TorrentEngineError.libtorrentUnavailable
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let valuePointer = handle.withCString {
            function(engine.rawValue, $0, &errorPointer)
        }
        return try string(from: valuePointer, errorPointer: errorPointer)
    }

    private func validateResult(_ result: Int32, errorPointer: UnsafeMutablePointer<CChar>?) throws {
        guard result == 0 else {
            throw nativeError(errorPointer)
        }
        if let errorPointer {
            stringFreeFunction?(errorPointer)
        }
    }

    private func string(
        from pointer: UnsafeMutablePointer<CChar>?,
        errorPointer: UnsafeMutablePointer<CChar>?
    ) throws -> String {
        guard let pointer else {
            throw nativeError(errorPointer)
        }
        let value = String(cString: pointer)
        stringFreeFunction?(pointer)
        if let errorPointer {
            stringFreeFunction?(errorPointer)
        }
        return value
    }

    private func nativeError(_ pointer: UnsafeMutablePointer<CChar>?) -> Error {
        guard let pointer else {
            return TorrentEngineError.libtorrentUnavailable
        }

        let message = String(cString: pointer)
        stringFreeFunction?(pointer)
        if message.contains("file_not_found") {
            return TorrentEngineError.unsupported(operation: message)
        }
        if message.contains("streaming_url_unavailable") {
            return TorrentEngineError.unsupported(operation: message)
        }
        return TorrentEngineError.unsupported(operation: message)
    }

    private static func openLibrary() -> UnsafeMutableRawPointer? {
        for url in libraryCandidates() {
            if FileManager.default.fileExists(atPath: url.path),
               let library = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) {
                return library
            }
        }
        return dlopen("CineFlowLibtorrentNative.framework/CineFlowLibtorrentNative", RTLD_NOW | RTLD_LOCAL)
    }

    private static func libraryCandidates() -> [URL] {
        var candidates: [URL] = []
        if let privateFrameworksURL = Bundle.main.privateFrameworksURL {
            candidates.append(privateFrameworksURL.appendingPathComponent("CineFlowLibtorrentNative.framework/CineFlowLibtorrentNative"))
        }
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("CineFlowLibtorrentNative.framework/CineFlowLibtorrentNative"))
        }
        candidates.append(URL(fileURLWithPath: "Vendor/CineFlowLibtorrentNative.xcframework/macos-arm64/CineFlowLibtorrentNative.framework/CineFlowLibtorrentNative"))
        return candidates
    }

    private static func symbol<T>(_ name: String, library: UnsafeMutableRawPointer?) -> T? {
        guard let library, let pointer = dlsym(library, name) else {
            return nil
        }
        return unsafeBitCast(pointer, to: T.self)
    }
}

private struct NativeTorrentStatusDTO: Decodable {
    let sessionId: String?
    let state: String?
    let downloadedBytes: Int64?
    let totalBytes: Int64?
    let bufferedBytes: Int64?
    let downloadSpeedBytesPerSecond: Int64?
    let uploadSpeedBytesPerSecond: Int64?
    let seeders: Int?
    let leechers: Int?
    let connectedPeers: Int?
    let availability: Double?
    let selectedFileId: String?
    let isSequentialDownloadEnabled: Bool?
    let streamingURL: String?

    static func decode(_ json: String) throws -> NativeTorrentStatusDTO {
        guard let data = json.data(using: .utf8) else {
            throw TorrentEngineError.unsupported(operation: "statusJSON")
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    func status(defaultSessionId: String) throws -> TorrentStatus {
        TorrentStatus(
            sessionId: sessionId ?? defaultSessionId,
            state: torrentState,
            progress: TorrentProgress(
                downloadedBytes: downloadedBytes ?? 0,
                totalBytes: totalBytes ?? 0,
                bufferedBytes: bufferedBytes ?? 0,
                downloadSpeedBytesPerSecond: downloadSpeedBytesPerSecond ?? 0,
                uploadSpeedBytesPerSecond: uploadSpeedBytesPerSecond ?? 0
            ),
            health: TorrentHealth(
                seeders: seeders ?? 0,
                leechers: leechers ?? 0,
                connectedPeers: connectedPeers ?? 0,
                availability: availability ?? 0
            ),
            selectedFileId: selectedFileId,
            isSequentialDownloadEnabled: isSequentialDownloadEnabled ?? false,
            streamingURL: try streamingURL.map { value in
                guard let url = URL(string: value) else {
                    throw TorrentEngineError.streamingURLUnavailable(sessionId: sessionId ?? defaultSessionId)
                }
                return url
            }
        )
    }

    private var torrentState: TorrentSessionState {
        switch state {
        case "idle": .idle
        case "connecting": .connecting
        case "metadataLoading", "metadata_loading", "loading_metadata": .metadataLoading
        case "checking": .checking
        case "downloading": .downloading
        case "buffering": .buffering
        case "streaming": .streaming
        case "stalled": .stalled
        case "paused": .paused
        case "seeding": .seeding
        case "completed": .completed
        case "stopped": .stopped
        case let state? where state.hasPrefix("error:"):
            .error(reason: String(state.dropFirst("error:".count)))
        case let state? where state.hasPrefix("failed:"):
            .failed(reason: String(state.dropFirst("failed:".count)))
        case let state?:
            .failed(reason: state)
        case nil:
            .idle
        }
    }
}

private struct NativeTorrentFileDTO: Decodable {
    let id: String
    let path: String
    let name: String?
    let lengthBytes: Int64
    let isMediaFile: Bool
    let priority: Int?
    let downloadedBytes: Int64?
    let totalBytes: Int64?
    let bufferedBytes: Int64?
    let downloadSpeedBytesPerSecond: Int64?
    let uploadSpeedBytesPerSecond: Int64?

    static func decode(_ json: String) throws -> [NativeTorrentFileDTO] {
        guard let data = json.data(using: .utf8) else {
            throw TorrentEngineError.unsupported(operation: "filesJSON")
        }
        return try JSONDecoder().decode([Self].self, from: data)
    }

    var file: TorrentFile {
        TorrentFile(
            id: id,
            path: path,
            name: name ?? URL(fileURLWithPath: path).lastPathComponent,
            lengthBytes: lengthBytes,
            isMediaFile: isMediaFile,
            priority: TorrentFilePriority(rawValue: priority ?? TorrentFilePriority.normal.rawValue) ?? .normal,
            progress: TorrentProgress(
                downloadedBytes: downloadedBytes ?? 0,
                totalBytes: totalBytes ?? lengthBytes,
                bufferedBytes: bufferedBytes ?? 0,
                downloadSpeedBytesPerSecond: downloadSpeedBytesPerSecond ?? 0,
                uploadSpeedBytesPerSecond: uploadSpeedBytesPerSecond ?? 0
            )
        )
    }
}
