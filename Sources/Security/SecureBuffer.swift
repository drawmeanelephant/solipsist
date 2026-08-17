import Foundation

/// A fixed-capacity byte buffer for holding sensitive secrets in memory.
///
/// Ensures memory is zeroed out immediately upon deallocation or when `wipe()` is explicitly called.
/// Implements `CustomStringConvertible` and `CustomDebugStringConvertible` to prevent accidental
/// secret exposure through string interpolation or logging.
public final class SecureBuffer: @unchecked Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private var buffer: UnsafeMutableRawBufferPointer?
    private let lock = NSLock()

    /// The number of valid bytes stored in this buffer.
    public private(set) var count: Int

    /// Whether this buffer is empty (has 0 bytes or has been wiped).
    public var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return count == 0 || buffer == nil
    }

    /// Initializes a `SecureBuffer` by copying the given bytes.
    public init(bytes: [UInt8]) {
        self.count = bytes.count
        if bytes.isEmpty {
            self.buffer = nil
        } else {
            let ptr = UnsafeMutableRawBufferPointer.allocate(byteCount: bytes.count, alignment: 1)
            bytes.withUnsafeBytes { src in
                ptr.copyMemory(from: src)
            }
            self.buffer = ptr
        }
    }

    /// Initializes a `SecureBuffer` from `Data`.
    public convenience init(data: Data) {
        let bytes = [UInt8](data)
        self.init(bytes: bytes)
    }

    /// Initializes a `SecureBuffer` from a UTF-8 string.
    public convenience init(utf8String string: String) {
        let bytes = Array(string.utf8)
        self.init(bytes: bytes)
    }

    deinit {
        wipe()
    }

    /// Accesses the underlying bytes in a closure.
    /// Returns `nil` if the buffer is empty or already wiped.
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R? {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer, count > 0 else {
            return nil
        }
        return try body(UnsafeRawBufferPointer(buffer))
    }

    /// Returns a copy of the secret bytes as an array.
    /// Callers are responsible for wiping their own copy.
    public func copyBytes() -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer, count > 0 else { return [] }
        return Array(buffer)
    }

    /// Explicitly overwrites memory with zeroes and deallocates the buffer.
    public func wipe() {
        lock.lock()
        defer { lock.unlock() }
        guard let buf = buffer else { return }

        // Zero the memory buffer using memset_s when available or explicit volatile zeroing
        #if canImport(Darwin)
            memset_s(buf.baseAddress, buf.count, 0, buf.count)
        #else
            if let base = buf.baseAddress {
                base.initializeMemory(as: UInt8.self, repeating: 0, count: buf.count)
            }
        #endif

        buf.deallocate()
        self.buffer = nil
        self.count = 0
    }

    // MARK: - Redaction

    public var description: String {
        "<SecureBuffer count=\(count)>"
    }

    public var debugDescription: String {
        "<SecureBuffer count=\(count)>"
    }
}
