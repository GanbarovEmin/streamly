import Foundation

public protocol ReleaseSelectionStoreProtocol: AnyObject {
    func releaseID(for mediaID: String) -> String?
    func setReleaseID(_ releaseID: String?, for mediaID: String)
}

public final class UserDefaultsReleaseSelectionStore: ReleaseSelectionStoreProtocol {
    private let userDefaults: UserDefaults
    private let keyPrefix = "streamly.releaseSelection."

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func releaseID(for mediaID: String) -> String? {
        userDefaults.string(forKey: keyPrefix + mediaID)
    }

    public func setReleaseID(_ releaseID: String?, for mediaID: String) {
        let key = keyPrefix + mediaID
        if let releaseID, !releaseID.isEmpty {
            userDefaults.set(releaseID, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
}
