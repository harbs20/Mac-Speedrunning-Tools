import CoreGraphics
import Foundation

struct TrackedWindow: Identifiable, Hashable, Sendable {
    let id: CGWindowID
    let ownerName: String
    let ownerPID: pid_t
    let title: String
    let frame: CGRect
    let layer: Int
    let alpha: Double
    let memoryUsage: Int

    var displayName: String {
        if title.isEmpty {
            return ownerName
        }
        return "\(ownerName) - \(title)"
    }

    var sizeDescription: String {
        "\(Int(frame.width)) x \(Int(frame.height))"
    }

    var targetIdentity: WindowTargetIdentity {
        WindowTargetIdentity(ownerName: ownerName, title: title)
    }
}

enum WindowAffectMode: String, CaseIterable, Codable, Identifiable {
    case allWindows
    case specifiedWindowsOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allWindows:
            return "Affect all windows"
        case .specifiedWindowsOnly:
            return "Affect specified windows only"
        }
    }
}

struct WindowTargetIdentity: Codable, Hashable, Identifiable, Sendable {
    var ownerName: String
    var title: String

    var id: String {
        "\(ownerName)\u{1f}\(title)"
    }

    var displayName: String {
        if title.isEmpty {
            return ownerName
        }
        return "\(ownerName) - \(title)"
    }

}
