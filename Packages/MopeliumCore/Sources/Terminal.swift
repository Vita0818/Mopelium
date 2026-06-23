import Foundation

public func out(_ text: String) {
    try? FileHandle.standardOutput.write(contentsOf: Data(text.utf8))
}

public func errOut(_ text: String) {
    try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
}

public func truncated(_ text: String, limit: Int = 500) -> String {
    guard text.count > limit else { return text }
    return String(text.prefix(limit)) + "..."
}
