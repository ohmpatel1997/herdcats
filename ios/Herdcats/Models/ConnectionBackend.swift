import Foundation

/// The runtime selected for one saved SSH connection.
enum ConnectionBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case tui
    case core

    var id: String { rawValue }
    var title: String {
        switch self {
        case .tui: "TUI"
        case .core: "Herdr Core"
        }
    }

    /// The runtime's name inside a sentence.
    var runtimeName: String {
        switch self {
        case .tui: "the Herdr TUI"
        case .core: "Herdr Core"
        }
    }
}
