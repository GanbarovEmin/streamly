import Foundation

public enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case updateAvailable(String)
    case upToDate
    case failed(String)
}
