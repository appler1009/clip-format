import XCTest
@testable import ClipFormatShared

final class JSONParserTests: XCTestCase {
    func testParsesObjectAndPreservesKeyOrder() throws {
        let value = try JSONParser.parse(#"{"b":1,"a":2,"c":3}"#)
        guard case .object(let members) = value else { return XCTFail("expected object") }
        XCTAssertEqual(members.map(\.key), ["b", "a", "c"])
    }

    func testParsesNestedArraysAndLiterals() throws {
        let value = try JSONParser.parse(#"[[1,2],{"ok":true,"nil":null},"x"]"#)
        XCTAssertEqual(value, .array([
            .array([.number("1"), .number("2")]),
            .object([(key: "ok", value: .bool(true)), (key: "nil", value: .null)]),
            .string("x")
        ]))
    }

    func testPreservesNumberLiterals() throws {
        let value = try JSONParser.parse(#"{"a":1.50,"b":1e9,"c":-0.0}"#)
        XCTAssertEqual(PrettyPrinter.minified(value), #"{"a":1.50,"b":1e9,"c":-0.0}"#)
    }

    func testDecodesSurrogatePairsAndEscapes() throws {
        let value = try JSONParser.parse(#"["😀","tab\there","é"]"#)
        XCTAssertEqual(value, .array([.string("😀"), .string("tab\there"), .string("é")]))
    }

    func testRejectsTrailingCommaWithPosition() {
        XCTAssertThrowsError(try JSONParser.parse("{\n  \"a\": 1,\n}")) { error in
            let parseError = error as? JSONParseError
            XCTAssertEqual(parseError?.line, 3)
            XCTAssertNotNil(parseError?.message)
        }
    }

    func testRejectsTrailingContentAndUnpairedSurrogate() {
        XCTAssertThrowsError(try JSONParser.parse("{} {}"))
        XCTAssertThrowsError(try JSONParser.parse(#"["\uD83D"]"#))
        XCTAssertThrowsError(try JSONParser.parse("[01]"))
        XCTAssertThrowsError(try JSONParser.parse("[1,]"))
    }
}

final class PrettyPrinterTests: XCTestCase {
    func testPrettyPrintsWithRequestedIndent() throws {
        let value = try JSONParser.parse(#"{"a":[1,{"b":null}],"c":{}}"#)
        XCTAssertEqual(PrettyPrinter.pretty(value, indent: 2), """
        {
          "a": [
            1,
            {
              "b": null
            }
          ],
          "c": {}
        }
        """)
        XCTAssertTrue(PrettyPrinter.pretty(value, indent: 4).contains("\n    \"a\": ["))
    }

    func testMinifyRoundTrip() throws {
        let source = #"{"list":[1,2,3],"nested":{"k":"v"}}"#
        let value = try JSONParser.parse(PrettyPrinter.pretty(try JSONParser.parse(source), indent: 4))
        XCTAssertEqual(PrettyPrinter.minified(value), source)
    }

    func testQuotesControlCharactersButNotEmoji() {
        XCTAssertEqual(PrettyPrinter.quote("a\u{01}b"), "\"a\\u0001b\"")
        XCTAssertEqual(PrettyPrinter.quote("héllo 😀"), "\"héllo 😀\"")
    }
}

final class JSONCanvasTests: XCTestCase {
    func testValidClipboardModel() {
        let document = JSONCanvas.model(from: "  {\"a\":1}  ")
        XCTAssertTrue(document.isValid)
        XCTAssertEqual(document.prettyText, "{\n  \"a\": 1\n}")
        XCTAssertEqual(document.minifiedText, #"{"a":1}"#)
    }

    func testNonJSONAndEmptyStates() {
        let text = JSONCanvas.model(from: "hello world")
        XCTAssertFalse(text.isValid)
        XCTAssertEqual(text.errorMessage, "Not JSON")

        let empty = JSONCanvas.model(from: "   \n ")
        XCTAssertFalse(empty.isValid)
        XCTAssertEqual(empty.errorMessage, "Clipboard is empty")

        // A bare literal is valid JSON but is not what "I copied some JSON" means.
        XCTAssertFalse(JSONCanvas.model(from: "42").isValid)
    }

    func testInvalidJSONReportsParsePosition() {
        let document = JSONCanvas.model(from: #"{"a": 1,}"#)
        XCTAssertFalse(document.isValid)
        XCTAssertTrue(document.errorMessage?.contains("line 1") == true)
    }

    func testHTMLEscapesAndColorsTokens() {
        let document = JSONCanvas.model(from: #"{"<k>":"a & b"}"#)
        let html = JSONCanvas.html(from: document, appearance: .dark)
        XCTAssertTrue(html.contains("&lt;k&gt;"))
        XCTAssertTrue(html.contains("a &amp; b"))
        XCTAssertTrue(html.contains("class=\"k\""))
        XCTAssertTrue(html.contains(Theme.dark.background.hexString))
        XCTAssertFalse(html.contains("prefers-color-scheme"))
    }

    func testHTMLAutoAppearanceShipsBothPalettes() {
        let html = JSONCanvas.html(from: JSONCanvas.model(from: "{}"), appearance: nil)
        XCTAssertTrue(html.contains("prefers-color-scheme: dark"))
        XCTAssertTrue(html.contains(Theme.light.key.hexString))
        XCTAssertTrue(html.contains(Theme.dark.key.hexString))
    }

    func testInvalidHTMLShowsExcerpt() {
        let html = JSONCanvas.html(from: JSONCanvas.model(from: "not json <x>"), appearance: .light)
        XCTAssertTrue(html.contains("Not JSON"))
        XCTAssertTrue(html.contains("not json &lt;x&gt;"))
    }

    func testDataModelFromUTF8File() {
        let data = Data(#"{"emoji":"😀"}"#.utf8)
        XCTAssertEqual(JSONCanvas.model(from: data).minifiedText, #"{"emoji":"😀"}"#)
    }

    func testTruncationAppendsNotice() {
        let tokens = PrettyPrinter.tokens(for: .array(Array(repeating: .number("1"), count: 200)), indent: 2)
        let truncated = JSONCanvas.truncate(tokens, toCharacters: 40)
        XCTAssertTrue(truncated.map(\.text).joined().hasSuffix("… truncated"))
        XCTAssertLessThan(truncated.count, tokens.count)
    }

    func testOversizedDocumentTruncatesFormattedOutput() {
        let big = "[" + Array(repeating: "\"0123456789\"", count: 60_000).joined(separator: ",") + "]"
        let document = JSONCanvas.model(from: big)
        XCTAssertTrue(document.isValid)
        XCTAssertTrue(document.isTruncated)
        let rendered = document.tokens.map(\.text).joined()
        XCTAssertLessThan(rendered.count, JSONCanvas.renderCharacterLimit + 100)
        XCTAssertTrue(rendered.hasSuffix("… truncated"))
        // The full text is still available for Copy Pretty.
        XCTAssertGreaterThan(document.prettyText?.count ?? 0, JSONCanvas.renderCharacterLimit)
    }

    func testHTMLUsesRequestedFontSizeAndTabSize() {
        let document = JSONCanvas.model(from: #"{"a":1}"#, indent: 4)
        let html = JSONCanvas.html(from: document, appearance: .light, fontSize: 18)
        XCTAssertTrue(html.contains("font: 18.0px/1.55"))
        XCTAssertTrue(html.contains("tab-size: 4"))
    }

    func testSharedFormattingPreferencesClampAndLoad() {
        XCTAssertEqual(SharedFormattingPreferences(indentWidth: 8, fontSize: 99).fontSize, AppGroup.maxFontSize)
        let suite = UserDefaults(suiteName: "clipformat.tests.prefs")!
        suite.removePersistentDomain(forName: "clipformat.tests.prefs")
        suite.set(4, forKey: AppGroup.Key.indentWidth)
        suite.set(18, forKey: AppGroup.Key.fontSize)
        XCTAssertEqual(SharedFormattingPreferences.load(from: suite),
                       SharedFormattingPreferences(indentWidth: 4, fontSize: 18))
    }

    func testHTMLKeepsOneSpanPerColouredRun() {
        let html = JSONCanvas.html(from: JSONCanvas.model(from: #"{"a":"b"}"#), appearance: .light)
        // Key, ':' and value each get one span; whitespace and newlines stay bare.
        XCTAssertTrue(html.contains(#"<span class="k">&quot;a&quot;</span><span class="p">:</span> <span class="s">&quot;b&quot;</span>"#))
        XCTAssertEqual(html.components(separatedBy: "<span").count - 1, 5)
    }

    func testDeepNestingIsRejectedNotCrashed() {
        let deep = String(repeating: "[", count: 5_000) + String(repeating: "]", count: 5_000)
        XCTAssertFalse(JSONCanvas.model(from: deep).isValid)
    }
}
