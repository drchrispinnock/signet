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
            if number.isJSONBoolean {
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
    /// A whole number the server sent that fits an `Int`; `nil` for anything else (NaN, infinity,
    /// fractions, values beyond 2^53 or `Int`), so a bad reply is an error rather than a trap (S20).
    var intValue: Int? {
        switch self {
        case .number(let n):
            guard n.isFinite, n == n.rounded(), abs(n) < 9_007_199_254_740_992 else { return nil }
            return Int(exactly: n)
        case .string(let s):
            return Int(s)
        default:
            return nil
        }
    }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o } else { return nil } }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }

    subscript(key: String) -> JSONValue? { objectValue?[key] }
}

extension NSNumber {
    /// Whether this number is a boolean rather than a count. On the Mac CFBoolean is an NSNumber
    /// subclass, told apart by type ID; elsewhere a boolean NSNumber reports Objective-C type `c`
    /// (signed char), which no JSON number decodes as.
    var isJSONBoolean: Bool {
        #if canImport(Darwin)
        CFGetTypeID(self) == CFBooleanGetTypeID()
        #else
        String(cString: objCType) == "c"
        #endif
    }

    /// The number as a `Decimal`. On the Mac this is `decimalValue`; swift-corelibs-foundation's
    /// `decimalValue` goes through binary floating point even for whole numbers (24666552157412
    /// reads back as 24666552157411.99872), so elsewhere whole numbers convert from their integer
    /// value and fractions from their shortest decimal text.
    var exactDecimal: Decimal {
        #if canImport(Darwin)
        decimalValue
        #else
        switch String(cString: objCType) {
        case "c", "s", "i", "l", "q": Decimal(int64Value)
        case "C", "S", "I", "L", "Q": Decimal(uint64Value)
        default: Decimal(string: stringValue, locale: Locale(identifier: "en_US_POSIX")) ?? decimalValue
        }
        #endif
    }
}
