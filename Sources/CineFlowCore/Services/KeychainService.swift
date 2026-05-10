import Foundation
import Security

public enum KeychainCredentialKind: String, Codable, CaseIterable, Hashable, Sendable {
    case sourceLoginPassword
    case sourceSessionCookies
    case apiToken
    case openSubtitles
    case futureSync
}

public struct KeychainCredential: Codable, Equatable, Sendable {
    public let accountID: String
    public var kind: KeychainCredentialKind
    public var sourceID: String?
    public var username: String?
    public var password: String?
    public var token: String?
    public var cookies: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        accountID: String,
        kind: KeychainCredentialKind,
        sourceID: String? = nil,
        username: String? = nil,
        password: String? = nil,
        token: String? = nil,
        cookies: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.accountID = accountID
        self.kind = kind
        self.sourceID = sourceID
        self.username = username
        self.password = password
        self.token = token
        self.cookies = cookies
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public protocol KeychainServiceProtocol: Sendable {
    func saveCredential(_ credential: KeychainCredential) async throws -> String
    func readCredential(accountID: String) async throws -> KeychainCredential?
    func updateCredential(_ credential: KeychainCredential) async throws
    func deleteCredential(accountID: String) async throws
    func deleteAllCineFlowCredentials() async throws
}

public enum KeychainServiceError: LocalizedError, Equatable, Sendable {
    case emptyAccountID
    case encodingFailure
    case decodingFailure
    case keychainFailure(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .emptyAccountID:
            "Keychain account id is empty."
        case .encodingFailure:
            "Credential could not be encoded for Keychain."
        case .decodingFailure:
            "Stored credential could not be decoded from Keychain."
        case .keychainFailure(let status):
            "Keychain operation failed with status \(status)."
        }
    }
}

extension KeychainServiceError: CineFlowErrorConvertible {
    public var cineFlowError: CineFlowError {
        CineFlowError(
            category: .permissions,
            technicalDescription: errorDescription ?? String(describing: self),
            userMessage: "CineFlow cannot access secure credentials.",
            recoverySuggestion: "Check Keychain and macOS permissions, then try again.",
            logLevel: .warning
        )
    }
}

public struct KeychainService: KeychainServiceProtocol {
    private let service: String

    public init(service: String = "com.cineflow.credentials") {
        self.service = service
    }

    public func saveCredential(_ credential: KeychainCredential) async throws -> String {
        guard !credential.accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KeychainServiceError.emptyAccountID
        }

        var credential = credential
        credential.updatedAt = Date()
        let data: Data
        do {
            data = try JSONEncoder().encode(credential)
        } catch {
            throw KeychainServiceError.encodingFailure
        }

        let query = baseQuery(accountID: credential.accountID)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainServiceError.keychainFailure(status)
        }

        return keychainID(for: credential.accountID)
    }

    public func readCredential(accountID: String) async throws -> KeychainCredential? {
        var query = baseQuery(accountID: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainServiceError.keychainFailure(status)
        }
        guard let data = result as? Data else {
            throw KeychainServiceError.decodingFailure
        }

        do {
            return try JSONDecoder().decode(KeychainCredential.self, from: data)
        } catch {
            throw KeychainServiceError.decodingFailure
        }
    }

    public func updateCredential(_ credential: KeychainCredential) async throws {
        _ = try await saveCredential(credential)
    }

    public func deleteCredential(accountID: String) async throws {
        let status = SecItemDelete(baseQuery(accountID: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.keychainFailure(status)
        }
    }

    public func deleteAllCineFlowCredentials() async throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.keychainFailure(status)
        }
    }

    private func baseQuery(accountID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID
        ]
    }

    private func keychainID(for accountID: String) -> String {
        "\(service):\(accountID)"
    }
}

public actor MockKeychainService: KeychainServiceProtocol {
    private var credentialsByAccountID: [String: KeychainCredential] = [:]
    private let service: String

    public init(service: String = "mock-keychain") {
        self.service = service
    }

    public func saveCredential(_ credential: KeychainCredential) async throws -> String {
        guard !credential.accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KeychainServiceError.emptyAccountID
        }
        credentialsByAccountID[credential.accountID] = credential
        return keychainID(for: credential.accountID)
    }

    public func readCredential(accountID: String) async throws -> KeychainCredential? {
        credentialsByAccountID[accountID]
    }

    public func updateCredential(_ credential: KeychainCredential) async throws {
        _ = try await saveCredential(credential)
    }

    public func deleteCredential(accountID: String) async throws {
        credentialsByAccountID[accountID] = nil
    }

    public func deleteAllCineFlowCredentials() async throws {
        credentialsByAccountID.removeAll()
    }

    private func keychainID(for accountID: String) -> String {
        "\(service):\(accountID)"
    }
}
