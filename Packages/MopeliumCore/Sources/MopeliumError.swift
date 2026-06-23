import Foundation

public enum MopeliumError: Error, Equatable, LocalizedError {
    case config(String)
    case provider(String)
    case network(String)
    case httpStatus(Int, String?)
    case decoding(String)
    case io(String)
    case usage(String)

    public var errorDescription: String? {
        switch self {
        case .config(let message):
            return message
        case .provider(let message):
            return "Provider error: \(message)"
        case .network(let message):
            return "Network error: \(message)"
        case .httpStatus(let status, let message):
            if let message, !message.isEmpty {
                return "HTTP \(status): \(message)"
            }
            return "HTTP \(status)"
        case .decoding(let message):
            return "Decoding error: \(message)"
        case .io(let message):
            return "I/O error: \(message)"
        case .usage(let message):
            return message
        }
    }
}
