struct PhotoPreviewTransitionState: Equatable {
    enum Phase: Equatable {
        case idle
        case opening
        case presented
        case preparingDismissal
        case closing
    }

    private(set) var phase: Phase = .idle

    var hidesSystemUI: Bool {
        phase == .presented
    }

    mutating func beginPresentation() -> Bool {
        guard phase == .idle else { return false }
        phase = .opening
        return true
    }

    mutating func finishPresentation() {
        guard phase == .opening else { return }
        phase = .presented
    }

    mutating func prepareDismissal() -> Bool {
        guard phase == .opening || phase == .presented else { return false }
        phase = .preparingDismissal
        return true
    }

    mutating func beginDismissal() -> Bool {
        guard phase == .preparingDismissal else { return false }
        phase = .closing
        return true
    }

    mutating func finishDismissal() {
        guard phase == .closing else { return }
        phase = .idle
    }
}
