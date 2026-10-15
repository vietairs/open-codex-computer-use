import Darwin
import Foundation

// Newline-delimited line I/O over the app-agent socket. Every writer ends each message with a
// newline, so a read that reaches end of stream without one is a truncated message from a peer
// that died mid-write, never a complete message.

/// Reads one `\n`-terminated line, without the newline. Returns nil at end of stream, including
/// when the stream ends in the middle of a line (the partial bytes are discarded), and when the
/// line is not valid UTF-8.
public func readAppAgentLine(_ file: UnsafeMutablePointer<FILE>) -> String? {
    var bytes: [UInt8] = []

    while true {
        let character = fgetc(file)
        if character == EOF {
            return nil
        }
        if character == 10 {
            return String(data: Data(bytes), encoding: .utf8)
        }
        bytes.append(UInt8(character))
    }
}

/// Writes `line` plus a newline and flushes. Returns false when the peer is gone and the bytes
/// could not be delivered.
@discardableResult
public func writeAppAgentLine(_ line: String, to file: UnsafeMutablePointer<FILE>) -> Bool {
    let output = line + "\n"
    let written = output.withCString { fputs($0, file) }
    let flushed = fflush(file)
    return written >= 0 && flushed == 0
}

/// Makes a write to `fileDescriptor` fail with EPIPE once the peer is gone, instead of raising SIGPIPE
/// and killing the writing process. Both ends of the app-agent socket need this: a proxy that dies
/// mid-call must not take the shared agent down when the agent writes the reply.
@discardableResult
public func disableAppAgentSocketSigPipe(_ fileDescriptor: Int32) -> Bool {
    var noSigPipe: Int32 = 1
    return setsockopt(fileDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size)) == 0
}
