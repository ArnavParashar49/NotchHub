import Foundation
import Testing
@testable import NotchHubSystem

@Suite("WebKitValueDecoder")
struct WebKitValueDecoderTests {

    private func u32(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
    private func latin1(_ s: String) -> [UInt8] { u32(UInt32(s.utf8.count) | 0x8000_0000) + Array(s.utf8) }
    private func utf16(_ s: String) -> [UInt8] {
        let units = Array(s.utf16)
        return u32(UInt32(units.count)) + units.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
    }

    @Test("decodes objects, strings, numbers, pooled keys and back-references")
    func decodesStructuredClone() throws {
        var bytes: [UInt8] = u32(15)          // version
        bytes += [2]                          // object
        bytes += latin1("sessionId") + [16] + latin1("sess_x")
        bytes += latin1("n") + [5] + u32(UInt32(bitPattern: -7))
        bytes += latin1("d") + [10] + withUnsafeBytes(of: (1.5).bitPattern.littleEndian) { Array($0) }
        bytes += latin1("title") + [16] + utf16("héllo")
        bytes += latin1("event") + [2]        // nested object
        bytes += u32(0xFFFF_FFFE) + [0]       // pooled key: "sessionId"
        bytes += [9]                          // true
        bytes += u32(0xFFFF_FFFF)             // end nested
        bytes += latin1("list") + [1] + u32(2) + u32(0) + [7] + u32(1) + [17] + u32(0xFFFF_FFFF)
        bytes += latin1("again") + [19] + [1] // back-reference to object #1 (the nested event)
        bytes += u32(0xFFFF_FFFF)             // end root

        let value = try #require(try WebKitValueDecoder.decode(Data(bytes)) as? [String: Any])
        #expect(value["sessionId"] as? String == "sess_x")
        #expect(value["n"] as? Int == -7)
        #expect(value["d"] as? Double == 1.5)
        #expect(value["title"] as? String == "héllo")
        #expect((value["event"] as? [String: Any])?["sessionId"] as? Bool == true)
        let list = try #require(value["list"] as? [Any])
        #expect(list.count == 2)
        #expect(list[0] as? Int == 1)
        #expect(list[1] as? String == "")
        #expect((value["again"] as? [String: Any])?["sessionId"] as? Bool == true)
    }

    @Test("an unsupported tag throws instead of guessing")
    func unsupportedTag() {
        let bytes: [UInt8] = u32(15) + [99]
        #expect(throws: WebKitValueDecoder.DecodeError.self) {
            _ = try WebKitValueDecoder.decode(Data(bytes))
        }
    }
}
