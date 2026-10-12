import Foundation

/// Validate resource bounds before JavaScript/SDK JSON parsing and recursive schema processing.
/// Syntax remains the parser's responsibility; scanning bytes also bounds long encrypted relay
/// strings before decryption, without allocating a second decoded object.
enum JSONBudget {
    static func accepts(_ data: Data, depthLimit: Int = 128, nodeLimit: Int = 250_000, stringLimit: Int = 1 << 20) -> Bool {
        var depth = 0, nodes = 0, quoted = false, escaped = false, stringBytes = 0
        for byte in data {
            if quoted {
                stringBytes += 1
                if stringBytes > stringLimit { return false }
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else {
                switch byte {
                case 34: quoted = true; stringBytes = 0
                case 91, 123:
                    depth += 1; nodes += 1
                    if depth > depthLimit || nodes > nodeLimit { return false }
                case 93, 125: depth -= 1
                case 44:
                    nodes += 1
                    if nodes > nodeLimit { return false }
                default: break
                }
            }
        }
        return true
    }
}
