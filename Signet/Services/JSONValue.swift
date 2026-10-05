import Foundation

/// A `Sendable` mirror of anything JavaScriptCore can hand back, so bridge results can cross
/// isolation boundaries under strict concurrency.
enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Converts the output of `JSValue.toObject()` (Foundation types) into a `JSONValue`.
    init(bridged value: Any?) {
        switch value {
        case nil, is NSNull:
            self = .null
        case let number as NSNumber:
            // CFBoolean is an NSNumber subclass; tell the two apart by type ID.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any?]:
            self = .array(array.map { JSONValue(bridged: $0) })
        case let dictionary as [String: Any?]:
            self = .object(dictionary.mapValues { JSONValue(bridged: $0) })
        default:
            self = .string(String(describing: value!))
        }
    }

    var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    var doubleValue: Double? { if case .number(let n) = self { return n } else { return nil } }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o } else { return nil } }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }

    subscript(key: String) -> JSONValue? { objectValue?[key] }
}
