import Foundation

// Pure state used by the player and deterministic lifecycle tests.
struct PlaybackSession {
    enum Phase { case stopped, waiting, playing, paused, failed }
    /// What the player should do after a stall or item failure on the current session.
    enum Recovery { case retry, fail }
    static let maxRetries = 2
    private(set) var id = UUID()
    private(set) var phase: Phase = .stopped
    /// Consecutive automatic re-tunes; cleared by reaching `.playing` or a viewer-initiated tune.
    private(set) var retries = 0
    var buffering: Bool { phase == .waiting }
    var reconnecting: Bool { buffering && retries > 0 }
    mutating func begin(automatic: Bool = false) {
        if !automatic { retries = 0 }
        id = UUID(); phase = .waiting
    }
    mutating func stop() { id = UUID(); phase = .stopped }
    @discardableResult mutating func receive(_ phase: Phase, session: UUID) -> Bool {
        guard session == id, self.phase != .stopped, self.phase != .failed else { return false }
        self.phase = phase
        if phase == .playing { retries = 0 }
        return true
    }
    /// The player item failed. A paused session fails outright so an automatic re-tune never overrides a pause.
    mutating func fail(session: UUID) -> Recovery? {
        let paused = phase == .paused
        guard receive(.failed, session: session) else { return nil }
        return paused ? .fail : recover()
    }
    /// The watchdog fired while still buffering.
    mutating func expire(session: UUID) -> Recovery? {
        guard session == id, buffering else { return nil }
        phase = .failed
        return recover()
    }
    private mutating func recover() -> Recovery {
        guard retries < Self.maxRetries else { return .fail }
        retries += 1
        return .retry
    }
}
