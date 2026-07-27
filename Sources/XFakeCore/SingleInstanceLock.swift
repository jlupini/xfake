import Foundation

/// Held for the life of the process; flock(2) releases automatically on
/// process death (including crashes), so a stale lock can never persist.
private var lockFileDescriptor: Int32 = -1

/// Takes an exclusive, non-blocking flock on
/// ~/Library/Application Support/xfake/xfake.lock. Returns false if another
/// xfake instance (CLI or menu bar app) already holds it — two instances
/// would each see the other's vendor-copied virtual display as glasses and
/// thrash teardown/rebuild against each other.
public func acquireSingleInstanceLock() -> Bool {
    guard lockFileDescriptor == -1 else { return true } // this process already holds it

    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("xfake", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
        return false
    }

    let path = dir.appendingPathComponent("xfake.lock").path
    let fd = open(path, O_CREAT | O_RDWR, 0o644)
    guard fd >= 0 else { return false }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
        close(fd)
        return false
    }
    lockFileDescriptor = fd // keep fd (and thus the lock) alive for process lifetime
    return true
}
