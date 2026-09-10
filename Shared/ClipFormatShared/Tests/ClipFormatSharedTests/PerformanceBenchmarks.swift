import ClipFormatShared
import XCTest

/// Wall-clock benches for the shared hot path. Run with:
/// `cd Shared/ClipFormatShared && swift test --filter PerformanceBenchmarks`
///
/// Numbers vary by machine; compare before/after on the same host.
final class PerformanceBenchmarks: XCTestCase {
    private lazy var largeJSON: String = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/ClipFormatSharedTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ClipFormatShared
            .deletingLastPathComponent() // Shared
            .appendingPathComponent("Fixtures/large.json")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{"fallback":true}"#
    }()

    private lazy var hugeJSON: String = {
        // ~1.2 MB of valid JSON — past the 256 KiB async threshold, under 32 MB.
        let row = #"{"id":12345,"name":"widget","ok":true,"tags":["a","b","c"],"n":1.5}"#
        return "[" + Array(repeating: row, count: 8_000).joined(separator: ",") + "]"
    }()

    private lazy var plainText: String = String(repeating: "not json at all. ", count: 4_000)

    func testBenchModelLargeFixture() {
        measure {
            let document = FormatCanvas.model(from: largeJSON)
            XCTAssertTrue(document.isValid)
            _ = document.tokens.count
        }
    }

    func testBenchModelHugeArray() {
        measure {
            let document = FormatCanvas.model(from: hugeJSON)
            XCTAssertTrue(document.isValid)
            _ = document.tokens.count
        }
    }

    func testBenchAttributedFromLarge() {
        let document = FormatCanvas.model(from: largeJSON)
        measure {
            let attributed = FormatCanvas.attributedString(from: document, appearance: .light)
            XCTAssertFalse(String(attributed.characters).isEmpty)
        }
    }

    /// Font size is applied by the host `Text`, so restyling must not rebuild
    /// the attributed string from tokens. This benches the colourised build
    /// once, then a trivial size change cost analogue (join characters only).
    func testBenchFontRestyleDoesNotRebuildTokens() {
        let document = FormatCanvas.model(from: largeJSON)
        let attributed = FormatCanvas.attributedString(from: document, appearance: .light)
        measure {
            // Host path: reuse attributed, only the view font changes.
            XCTAssertEqual(String(attributed.characters).utf8.count,
                           document.tokens.reduce(0) { $0 + $1.text.utf8.count })
        }
    }

    func testBenchHTMLFromLarge() {
        let document = FormatCanvas.model(from: largeJSON)
        measure {
            let html = FormatCanvas.html(from: document, appearance: .dark)
            XCTAssertTrue(html.contains("<pre"))
        }
    }

    func testBenchRejectPlainText() {
        measure {
            let document = FormatCanvas.model(from: plainText)
            XCTAssertFalse(document.isValid)
        }
    }

    func testBenchCopyPrettyHuge() {
        let document = FormatCanvas.model(from: hugeJSON)
        measure {
            XCTAssertNotNil(document.prettyText)
        }
    }
}
