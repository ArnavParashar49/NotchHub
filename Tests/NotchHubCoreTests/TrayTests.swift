import Foundation
import Testing
@testable import NotchHubCore

@Suite("Tray")
struct TrayTests {

    private func clip(_ text: String, kind: ClipKind = .text, pinned: Bool = false, ageSeconds: TimeInterval = 0) -> TrayClip {
        TrayClip(kind: kind, text: text, pinned: pinned, createdAt: Date().addingTimeInterval(-ageSeconds))
    }

    // MARK: - What the Tray stores

    @Test("the Tray holds text and nothing else")
    func textOnlyKinds() {
        // Clipboard storage, full stop: there is no kind that refers to a file
        // on disk, so the Tray cannot leave anything behind it or show an entry
        // whose payload has gone.
        #expect(Set(ClipKind.allCases) == [.text, .link, .color])
        #expect(Set(TrayFilter.allCases) == [.all, .texts, .links, .colors])
        for kind in ClipKind.allCases {
            #expect(!kind.symbol.isEmpty)
        }
    }

    @Test("each filter admits exactly its own kind, and All admits everything")
    func filters() {
        let all: [ClipKind: TrayClip] = [
            .text: clip("hello"),
            .link: clip("https://example.com", kind: .link),
            .color: clip("#FF8800", kind: .color),
        ]
        for (kind, item) in all {
            #expect(TrayFilter.all.includes(item))
            for filter in TrayFilter.allCases where filter != .all {
                let shouldMatch = (filter == .texts && kind == .text)
                    || (filter == .links && kind == .link)
                    || (filter == .colors && kind == .color)
                #expect(filter.includes(item) == shouldMatch, "\(filter) vs \(kind)")
            }
        }
    }

    // MARK: - History behaviour

    @Test("re-copying the same thing refreshes it rather than adding a twin")
    func repeatedCopyCollapses() {
        let store = TrayStore()
        store.add(clip("same"))
        store.add(clip("same"))
        store.add(clip("different"))
        store.add(clip("same"))
        // The two adjacent "same" copies collapse; the later one, after another
        // clip came between, is a genuinely new entry.
        #expect(store.clips.count == 3)
        #expect(store.clips.first?.text == "same")
    }

    @Test("unpinned clips are capped at the capacity; pinned ones are free")
    func evictionKeepsPinned() {
        let store = TrayStore()
        store.add(clip("pinned one", pinned: true))
        for index in 0..<(TrayStore.capacity + 25) {
            store.add(clip("clip \(index)"))
        }
        #expect(store.unpinnedCount == TrayStore.capacity)
        #expect(store.pinnedCount == 1)
        #expect(store.clips.contains { $0.text == "pinned one" }, "a pinned clip was evicted")
        // The OLDEST unpinned ones are the ones that went.
        #expect(!store.clips.contains { $0.text == "clip 0" })
        #expect(store.clips.contains { $0.text == "clip \(TrayStore.capacity + 24)" })
    }

    @Test("clearing keeps pinned clips")
    func clearKeepsPinned() {
        let store = TrayStore()
        store.add(clip("keep me", pinned: true))
        store.add(clip("throw me"))
        store.clear()
        #expect(store.clips.map(\.text) == ["keep me"])
    }

    @Test("search is case- and diacritic-insensitive, and respects the filter")
    func search() {
        let store = TrayStore()
        store.add(clip("Café Terrace"))
        store.add(clip("https://example.com/cafe", kind: .link))
        store.add(clip("#CAFE00", kind: .color))

        #expect(store.search(query: "cafe").count == 3, "diacritics or case blocked a match")
        #expect(store.search(query: "cafe", filter: .links).count == 1)
        #expect(store.search(query: "nothing here").isEmpty)
        // An empty query is not a filter.
        #expect(store.search(query: "   ").count == 3)
    }

    @Test("pinned clips sort ahead of newer unpinned ones")
    func pinnedSortFirst() {
        let store = TrayStore()
        store.add(clip("old but pinned", pinned: true, ageSeconds: 600))
        store.add(clip("brand new"))
        #expect(store.search().map(\.text) == ["old but pinned", "brand new"])
    }

    @Test("bringing a clip to the front does not duplicate it")
    func moveToFront() {
        let store = TrayStore()
        store.add(clip("first"))
        store.add(clip("second"))
        let target = store.clips.last!
        store.moveToFront(id: target.id)
        #expect(store.clips.count == 2)
        #expect(store.clips.first?.id == target.id)
    }

    // MARK: - Display

    @Test("a long or multi-line clip is summarised to one readable line")
    func displayTitle() {
        let multiline = clip("\n\n   first real line   \nsecond line")
        #expect(multiline.displayTitle == "first real line")

        let long = clip(String(repeating: "a", count: 300))
        #expect(long.displayTitle.count <= 121)
        #expect(long.displayTitle.hasSuffix("…"))

        // A link and a colour are shown verbatim — truncating either loses the
        // thing that identifies it.
        #expect(clip("https://example.com/x", kind: .link).displayTitle == "https://example.com/x")
        #expect(clip("#FF8800", kind: .color).displayTitle == "#FF8800")

        // Nothing but whitespace still gets a label rather than an empty row.
        #expect(clip("   \n  ").displayTitle == "Text")
    }

    @Test("the subtitle names the source app and the size, when known")
    func displaySubtitle() {
        var full = clip("x")
        full.sourceApp = "Safari"
        full.byteSize = 2048
        #expect(full.displaySubtitle == "Safari · 2 KB")

        var bare = clip("x")
        bare.sourceApp = nil
        bare.byteSize = nil
        #expect(bare.displaySubtitle == nil)

        #expect(TrayClip.byteLabel(812) == "812 B")
    }

    // MARK: - Privacy

    @Test("a password manager's copy never enters the Tray")
    func privacyStillHolds() {
        // Unchanged by the move to text-only, and worth pinning down: these
        // markers are the whole reason a clipboard history is safe to keep.
        #expect(ClipboardPrivacy.shouldIgnore(types: ["org.nspasteboard.ConcealedType"], sourceBundleID: nil))
        #expect(ClipboardPrivacy.shouldIgnore(types: [], sourceBundleID: "com.1password.1password"))
        #expect(!ClipboardPrivacy.shouldIgnore(types: ["public.utf8-plain-text"], sourceBundleID: "com.apple.Safari"))
    }
}
