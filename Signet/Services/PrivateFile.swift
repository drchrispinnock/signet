import Foundation

/// Files that hold secrets or wallet state are created private from the first byte (S10):
/// the temporary file is opened with `O_CREAT | O_EXCL | O_NOFOLLOW` and mode 0600 before
/// anything is written, synced, then renamed over the target (which keeps that mode), and the
/// directory is synced too. Directories we write such files into are made 0700 when we own them.
enum PrivateFile {
    enum FileError: LocalizedError {
        case cannotCreate(String, Int32)
        case cannotRename(String, Int32)
        case unsafeDirectory(String)

        var errorDescription: String? {
            switch self {
            case .cannotCreate(let path, let code): "Could not create \(path): \(String(cString: strerror(code)))."
            case .cannotRename(let path, let code): "Could not replace \(path): \(String(cString: strerror(code)))."
            case .unsafeDirectory(let path): "\(path) is not a private directory owned by you; refusing to write secrets there."
            }
        }
    }

    static let temporarySuffix = ".tmp"

    /// Creates `directory` if needed (mode 0700) and, when it already exists and is ours, drops
    /// any group/other permission bits it has picked up. A directory owned by someone else, or
    /// a symlink, is refused.
    static func hardenDirectory(_ directory: URL) throws {
        let path = directory.path
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if !fm.fileExists(atPath: path, isDirectory: &isDirectory) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == geteuid() else {
            throw FileError.unsafeDirectory(path)
        }
        if info.st_mode & 0o077 != 0 {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        }
    }

    /// Writes `data` to `url` atomically and privately. The parent directory is hardened first.
    static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try hardenDirectory(directory)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)\(temporarySuffix)")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw FileError.cannotCreate(temporary.path, errno) }
        var ok = false
        defer { if !ok { unlink(temporary.path) } }
        do {
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    #if canImport(Darwin)
                    let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                    #else
                    let written = Glibc.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                    #endif
                    guard written > 0 else { throw FileError.cannotCreate(temporary.path, errno) }
                    offset += written
                }
            }
            guard fchmod(fd, 0o600) == 0, fsync(fd) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            close(fd)
        } catch {
            close(fd)
            throw error
        }
        guard rename(temporary.path, url.path) == 0 else { throw FileError.cannotRename(url.path, errno) }
        ok = true
        try syncDirectory(directory)
    }

    /// Reads a file, refusing symlinks, so a planted link cannot redirect a read elsewhere.
    static func read(_ url: URL) throws -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw FileError.cannotCreate(url.path, errno)
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= 32 << 20 else {
            throw CocoaError(.fileReadTooLarge)
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        var bytes = Data()
        while let chunk = try handle.read(upToCount: 32 * 1024), !chunk.isEmpty {
            guard bytes.count + chunk.count <= 32 << 20 else { throw CocoaError(.fileReadTooLarge) }
            bytes.append(chunk)
        }
        return bytes
    }

    /// Removes temporaries a crash may have left for `names` in `directory`. Call it only while
    /// holding whatever lock guards writes there, so a live temporary is never swept.
    static func removeStaleTemporaries(in directory: URL, for names: [String]) {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for entry in entries where entry.hasSuffix(temporarySuffix) {
            for name in names where entry.hasPrefix(".\(name).") {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry))
            }
        }
    }

    static func syncDirectory(_ directory: URL) throws {
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
