import Foundation

/// Decodes WebKit's structured-clone wire format (`SerializedScriptValue`),
/// the format WebKit stores IndexedDB record values in.
///
/// Only the JSON-like subset is supported — objects, arrays, strings, numbers,
/// booleans, null/undefined, dates and object back-references — which is all
/// an app's plain event records contain. Anything else throws, and callers skip
/// the record.
enum WebKitValueDecoder {

    enum DecodeError: Error {
        case truncated
        case unsupportedTag(UInt8)
    }

    static func decode(_ data: Data) throws -> Any {
        var cursor = Cursor(bytes: [UInt8](data))
        _ = try cursor.u32() // format version
        return try cursor.value()
    }

    private struct Cursor {
        static let terminator: UInt32 = 0xFFFF_FFFF
        static let stringPool: UInt32 = 0xFFFF_FFFE
        static let nonIndexProperties: UInt32 = 0xFFFF_FFFD

        let bytes: [UInt8]
        var position = 0
        var pool: [String] = []
        var objects: [Any] = []

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func u8() throws -> UInt8 {
            guard position < bytes.count else { throw DecodeError.truncated }
            defer { position += 1 }
            return bytes[position]
        }

        mutating func u16() throws -> UInt16 {
            UInt16(try u8()) | UInt16(try u8()) << 8
        }

        mutating func u32() throws -> UInt32 {
            guard position + 4 <= bytes.count else { throw DecodeError.truncated }
            var value: UInt32 = 0
            for i in 0..<4 { value |= UInt32(bytes[position + i]) << (8 * UInt32(i)) }
            position += 4
            return value
        }

        mutating func f64() throws -> Double {
            guard position + 8 <= bytes.count else { throw DecodeError.truncated }
            var bits: UInt64 = 0
            for i in 0..<8 { bits |= UInt64(bytes[position + i]) << (8 * UInt64(i)) }
            position += 8
            return Double(bitPattern: bits)
        }

        /// A pool / reference index, sized by how many entries exist.
        mutating func index(count: Int) throws -> Int {
            if count <= 0xFF { return Int(try u8()) }
            if count <= 0xFFFF { return Int(try u16()) }
            return Int(try u32())
        }

        mutating func string(length rawLength: UInt32? = nil) throws -> String {
            let length = try rawLength ?? u32()
            if length == Self.stringPool {
                let i = try index(count: pool.count)
                guard i < pool.count else { throw DecodeError.truncated }
                return pool[i]
            }
            let text: String
            if length & 0x8000_0000 != 0 {
                let n = Int(length & 0x7FFF_FFFF)
                guard position + n <= bytes.count else { throw DecodeError.truncated }
                // 8-bit strings are Latin-1: each byte is its own code point.
                text = String(String.UnicodeScalarView(bytes[position..<(position + n)].map { Unicode.Scalar($0) }))
                position += n
            } else {
                let n = Int(length) * 2
                guard position + n <= bytes.count else { throw DecodeError.truncated }
                let units = stride(from: position, to: position + n, by: 2).map {
                    UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8
                }
                text = String(decoding: units, as: UTF16.self)
                position += n
            }
            pool.append(text)
            return text
        }

        mutating func properties(into object: inout [String: Any]) throws {
            while true {
                let key = try u32()
                if key == Self.terminator { return }
                let name = try string(length: key)
                object[name] = try value()
            }
        }

        mutating func value() throws -> Any {
            let tag = try u8()
            switch tag {
            case 1: // array
                let length = Int(try u32())
                let slot = objects.count
                objects.append(NSNull())
                var array = [Any](repeating: NSNull(), count: min(length, 100_000))
                while true {
                    let key = try u32()
                    if key == Self.terminator { break }
                    if key == Self.nonIndexProperties {
                        var ignored: [String: Any] = [:]
                        try properties(into: &ignored)
                        break
                    }
                    let element = try value()
                    if Int(key) < array.count { array[Int(key)] = element }
                }
                objects[slot] = array
                return array
            case 2: // object
                let slot = objects.count
                objects.append(NSNull())
                var object: [String: Any] = [:]
                try properties(into: &object)
                objects[slot] = object
                return object
            case 3, 4: return NSNull()                     // undefined, null
            case 5: return Int(Int32(bitPattern: try u32())) // int32
            case 6: return 0
            case 7: return 1
            case 8: return false
            case 9: return true
            case 10, 11: return try f64()                  // double, date (ms)
            case 16: return try string()
            case 17: return ""
            case 19:
                let i = try index(count: objects.count)
                guard i < objects.count else { throw DecodeError.truncated }
                return objects[i]
            default:
                throw DecodeError.unsupportedTag(tag)
            }
        }
    }
}
