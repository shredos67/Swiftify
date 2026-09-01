import Foundation
import Security

struct StoredSpotifyCredentials: Codable {
    let clientID: String
    let refreshToken: String
    let authorizationVersion: Int?

    init(
        clientID: String,
        refreshToken: String,
        authorizationVersion: Int
    ) {
        self.clientID = clientID
        self.refreshToken = refreshToken
        self.authorizationVersion = authorizationVersion
    }
}

enum SpotifyCredentialStore {
    private static let service = "dev.addenator.Swiftify.spotify"
    private static let playbackAccount = "spotify-oauth"
    private static let libraryAccount = "spotify-library-oauth"

    static func loadPlayback() throws -> StoredSpotifyCredentials? {
        try load(account: playbackAccount)
    }

    static func savePlayback(_ credentials: StoredSpotifyCredentials) throws {
        try save(credentials, account: playbackAccount)
    }

    static func loadLibrary() throws -> StoredSpotifyCredentials? {
        try load(account: libraryAccount)
    }

    static func saveLibrary(_ credentials: StoredSpotifyCredentials) throws {
        try save(credentials, account: libraryAccount)
    }

    static func deleteAll() throws {
        for account in [playbackAccount, libraryAccount] {
            let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SpotifyCredentialStoreError(operation: "delete", status: status)
            }
        }
    }

    private static func load(account: String) throws -> StoredSpotifyCredentials? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw SpotifyCredentialStoreError(operation: "load", status: status)
        }

        return try JSONDecoder().decode(StoredSpotifyCredentials.self, from: data)
    }

    private static func save(_ credentials: StoredSpotifyCredentials, account: String) throws {
        let data = try JSONEncoder().encode(credentials)
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let query = baseQuery(account: account)
        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw SpotifyCredentialStoreError(operation: "save", status: updateStatus)
        }

        var item = query
        values.forEach { item[$0.key] = $0.value }

        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SpotifyCredentialStoreError(operation: "save", status: addStatus)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

private struct SpotifyCredentialStoreError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return "Could not \(operation) the saved Spotify login: \(detail)"
    }
}
