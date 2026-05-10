import Foundation
import XCTest

enum TestFixtures {
    static func string(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            XCTFail("Missing test fixture: \(name)", file: file, line: line)
            throw FixtureError.missing(name)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private enum FixtureError: Error {
    case missing(String)
}
