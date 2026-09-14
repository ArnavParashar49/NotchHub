import Foundation

/// One 16×16 frame of the pixel pet, decoded from `PetArt`.
///
/// Stored as horizontal runs of same-coloured pixels, so the renderer fills a
/// few dozen rectangles per frame instead of 256 individual pixels. A name
/// ending in `~` is the frame mirrored left-to-right: the pet facing the other
/// way, or living on the other side of the notch.
public struct PetFrame: Equatable, Sendable {
    public static let size = 16
    /// Appended to a frame name to draw it mirrored.
    public static let mirrorSuffix = "~"

    public struct Run: Equatable, Sendable {
        public let x: Int
        public let y: Int
        public let length: Int
        /// 0xRRGGBB.
        public let color: UInt32
    }

    public let runs: [Run]

    public init(rows: [String], palette: [Character: UInt32]) {
        var runs: [Run] = []
        for (y, row) in rows.prefix(Self.size).enumerated() {
            let pixels = Array(row.prefix(Self.size))
            var x = 0
            while x < pixels.count {
                guard let color = palette[pixels[x]] else {
                    x += 1 // transparent
                    continue
                }
                var length = 1
                while x + length < pixels.count, palette[pixels[x + length]] == color {
                    length += 1
                }
                runs.append(Run(x: x, y: y, length: length, color: color))
                x += length
            }
        }
        self.runs = runs
    }

    init(runs: [Run]) {
        self.runs = runs
    }

    /// The frame flipped left-to-right.
    public var mirrored: PetFrame {
        PetFrame(runs: runs.map { Run(x: Self.size - $0.x - $0.length, y: $0.y, length: $0.length, color: $0.color) })
    }

    /// Every frame in the art set, decoded once on first use.
    public static let all: [String: PetFrame] = PetArt.frames.mapValues { PetFrame(rows: $0, palette: PetArt.palette) }

    private static let allMirrored: [String: PetFrame] = all.mapValues(\.mirrored)

    public static func named(_ name: String) -> PetFrame? {
        if name.hasSuffix(mirrorSuffix) {
            return allMirrored[String(name.dropLast(mirrorSuffix.count))]
        }
        return all[name]
    }

    /// `name`, flipped when `mirrored` — a mirrored frame mirrored again is the
    /// original.
    public static func name(_ name: String, mirrored: Bool) -> String {
        guard mirrored else { return name }
        return name.hasSuffix(mirrorSuffix) ? String(name.dropLast(mirrorSuffix.count)) : name + mirrorSuffix
    }
}
