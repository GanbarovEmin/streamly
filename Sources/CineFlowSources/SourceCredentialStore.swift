import CineFlowCore
import Foundation

public protocol SourceCredentialStoreProtocol: Sendable {
    func save(credentials: SourceCredentials, for sourceId: String) async throws -> String
    func credentials(for sourceId: String) async throws -> SourceCredentials?
    func deleteCredentials(for sourceId: String) async throws
}

public struct KeychainSourceCredentialStore: SourceCredentialStoreProtocol {
    private let keychainService: any KeychainServiceProtocol

    public init(keychainService: any KeychainServiceProtocol = KeychainService()) {
        self.keychainService = keychainService
    }

    public func save(credentials: SourceCredentials, for sourceId: String) async throws -> String {
        try await keychainService.saveCredential(
            KeychainCredential(
                accountID: accountID(for: sourceId),
                kind: credentials.password == nil && credentials.token == nil && !credentials.cookies.isEmpty ? .sourceSessionCookies : .sourceLoginPassword,
                sourceID: sourceId,
                username: credentials.username,
                password: credentials.password,
                token: credentials.token,
                cookies: credentials.cookies
            )
        )
    }

    public func credentials(for sourceId: String) async throws -> SourceCredentials? {
        guard let credential = try await keychainService.readCredential(accountID: accountID(for: sourceId)) else {
            return nil
        }
        return SourceCredentials(
            username: credential.username,
            password: credential.password,
            token: credential.token,
            cookies: credential.cookies
        )
    }

    public func deleteCredentials(for sourceId: String) async throws {
        try await keychainService.deleteCredential(accountID: accountID(for: sourceId))
    }

    private func accountID(for sourceId: String) -> String {
        "source:\(sourceId)"
    }
}

public actor InMemorySourceCredentialStore: SourceCredentialStoreProtocol {
    private var credentialsBySourceID: [String: SourceCredentials] = [:]

    public init() {}

    public func save(credentials: SourceCredentials, for sourceId: String) async throws -> String {
        credentialsBySourceID[sourceId] = credentials
        return "memory:\(sourceId)"
    }

    public func credentials(for sourceId: String) async throws -> SourceCredentials? {
        credentialsBySourceID[sourceId]
    }

    public func deleteCredentials(for sourceId: String) async throws {
        credentialsBySourceID[sourceId] = nil
    }
}
