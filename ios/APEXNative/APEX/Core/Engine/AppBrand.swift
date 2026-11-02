import Foundation

enum AppBrand {
    static let name = "FITR MAX"
    private static let legacyNames = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_./])(?:APEX|FitDee|FITR-D|FITR-MAX)(?![A-Za-z0-9_]|[./][A-Za-z0-9_])"#
    )

    /// Presentation only. Persisted identifiers, Health metadata and user data stay intact.
    static func displayText(_ value: String) -> String {
        legacyNames.stringByReplacingMatches(in: value,
            range: NSRange(value.startIndex..., in: value), withTemplate: name)
    }
}
