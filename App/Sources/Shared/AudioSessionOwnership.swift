import Foundation

@MainActor enum AudioSessionOwnership {
    private static var owner: UUID?
    private static var release: (() -> Void)?

    static func isOwner(_ id: UUID) -> Bool { owner == id }

    static func claim(_ id: UUID, stopPrevious: @escaping () -> Void) {
        guard owner != id else { return }
        let previous = release
        owner = nil; release = nil
        previous?()
        owner = id; release = stopPrevious
    }

    static func relinquish(_ id: UUID) {
        guard owner == id else { return }
        owner = nil; release = nil
    }
}
