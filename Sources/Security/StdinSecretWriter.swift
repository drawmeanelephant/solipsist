import Foundation

/// Errors that can occur when streaming secrets to stdin.
public enum StdinSecretWriterError: Error, Equatable, Sendable {
    case emptySecret
    case writeFailed(String)
}

/// Utility for safely streaming secrets to a child process stdin `FileHandle` / pipe.
///
/// Ensures secrets are written directly without intermediate logging, string allocation,
/// or persistence, and immediately flushes and signals EOF if configured.
public enum StdinSecretWriter {

    /// Writes the contents of `secret` to the given file handle.
    ///
    /// - Parameters:
    ///   - secret: The secret buffer to write.
    ///   - handle: The write handle (e.g. write end of child process stdin pipe).
    ///   - appendNewline: Whether to append a newline byte (`0x0A`) after writing the secret. Defaults to `true`.
    ///   - closeAfterWriting: Whether to close the file handle after writing to signal EOF. Defaults to `true`.
    public static func writeSecret(
        _ secret: SecureBuffer,
        to handle: FileHandle,
        appendNewline: Bool = true,
        closeAfterWriting: Bool = true
    ) throws {
        guard !secret.isEmpty else {
            throw StdinSecretWriterError.emptySecret
        }

        try secret.withUnsafeBytes { rawBytes in
            guard let baseAddress = rawBytes.baseAddress, rawBytes.count > 0 else {
                throw StdinSecretWriterError.emptySecret
            }

            let fd = handle.fileDescriptor
            var bytesWritten = 0
            let totalBytes = rawBytes.count

            while bytesWritten < totalBytes {
                let chunkPtr = baseAddress.advanced(by: bytesWritten)
                let remaining = totalBytes - bytesWritten
                let result = write(fd, chunkPtr, remaining)
                if result < 0 {
                    let err = errno
                    throw StdinSecretWriterError.writeFailed("POSIX write failed with errno: \(err)")
                }
                bytesWritten += result
            }

            if appendNewline {
                var newlineByte: UInt8 = 0x0A
                _ = withUnsafeBytes(of: &newlineByte) { nlPtr in
                    write(fd, nlPtr.baseAddress, 1)
                }
            }
        }

        if closeAfterWriting {
            do {
                try handle.close()
            } catch {
                throw StdinSecretWriterError.writeFailed("Failed to close file handle: \(error)")
            }
        }
    }

    /// Writes the secret to `handle` and immediately calls `wipe()` on the `secret` buffer.
    public static func writeAndWipe(
        _ secret: SecureBuffer,
        to handle: FileHandle,
        appendNewline: Bool = true,
        closeAfterWriting: Bool = true
    ) throws {
        defer {
            secret.wipe()
        }
        try writeSecret(
            secret,
            to: handle,
            appendNewline: appendNewline,
            closeAfterWriting: closeAfterWriting
        )
    }
}
