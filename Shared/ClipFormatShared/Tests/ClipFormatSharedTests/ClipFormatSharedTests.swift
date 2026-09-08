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

final class FormatCanvasTests: XCTestCase {
    func testValidClipboardModel() {
        let document = FormatCanvas.model(from: "  {\"a\":1}  ")
        XCTAssertTrue(document.isValid)
        XCTAssertEqual(document.prettyText, "{\n  \"a\": 1\n}")
        XCTAssertEqual(document.minifiedText, #"{"a":1}"#)
    }

    func testNonJSONAndEmptyStates() {
        let text = FormatCanvas.model(from: "hello world")
        XCTAssertFalse(text.isValid)
        XCTAssertEqual(text.errorMessage, "Not JSON")

        let empty = FormatCanvas.model(from: "   \n ")
        XCTAssertFalse(empty.isValid)
        XCTAssertEqual(empty.errorMessage, "Clipboard is empty")

        // A bare literal is valid JSON but is not what "I copied some JSON" means.
        XCTAssertFalse(FormatCanvas.model(from: "42").isValid)
    }

    func testInvalidJSONReportsParsePosition() {
        // Not a trailing comma any more: that is valid JSONC now, and this
        // test is about the position in the message, not about which shapes
        // are accepted.
        let document = FormatCanvas.model(from: #"{"a": }"#)
        XCTAssertFalse(document.isValid)
        XCTAssertTrue(document.errorMessage?.contains("line 1") == true)
    }

    func testHTMLEscapesAndColorsTokens() {
        let document = FormatCanvas.model(from: #"{"<k>":"a & b"}"#)
        let html = FormatCanvas.html(from: document, appearance: .dark)
        XCTAssertTrue(html.contains("&lt;k&gt;"))
        XCTAssertTrue(html.contains("a &amp; b"))
        XCTAssertTrue(html.contains("class=\"k\""))
        XCTAssertTrue(html.contains(Theme.dark.background.hexString))
        XCTAssertFalse(html.contains("prefers-color-scheme"))
    }

    func testHTMLAutoAppearanceShipsBothPalettes() {
        let html = FormatCanvas.html(from: FormatCanvas.model(from: "{}"), appearance: nil)
        XCTAssertTrue(html.contains("prefers-color-scheme: dark"))
        XCTAssertTrue(html.contains(Theme.light.key.hexString))
        XCTAssertTrue(html.contains(Theme.dark.key.hexString))
    }

    func testInvalidHTMLShowsExcerpt() {
        let html = FormatCanvas.html(from: FormatCanvas.model(from: "not json <x>"), appearance: .light)
        XCTAssertTrue(html.contains("Not JSON"))
        XCTAssertTrue(html.contains("not json &lt;x&gt;"))
    }

    func testDataModelFromUTF8File() {
        let data = Data(#"{"emoji":"😀"}"#.utf8)
        XCTAssertEqual(FormatCanvas.model(from: data).minifiedText, #"{"emoji":"😀"}"#)
    }

    // MARK: - JSON with comments

    func testParsesLineComments() {
        let document = FormatCanvas.model(from: """
        {
          // the port the dev server listens on
          "port": 3000, // trailing note
          "host": "localhost"
        }
        """)
        XCTAssertTrue(document.isValid)
        XCTAssertEqual(document.kind, .jsonc)
        XCTAssertEqual(document.minifiedText, #"{"port":3000,"host":"localhost"}"#)
    }

    func testParsesBlockComments() {
        let document = FormatCanvas.model(from: "/* header */ {\"a\": /* inline */ 1}")
        XCTAssertEqual(document.kind, .jsonc)
        XCTAssertEqual(document.minifiedText, #"{"a":1}"#)
    }

    func testCommentMarkersInsideStringsAreJustText() {
        let document = FormatCanvas.model(from: #"{"url":"https://example.com//path","note":"/* not a comment */"}"#)
        // Strict JSON already, so no comment handling is involved at all.
        XCTAssertEqual(document.kind, .json)
        XCTAssertEqual(document.value, .object([
            (key: "url", value: .string("https://example.com//path")),
            (key: "note", value: .string("/* not a comment */"))
        ]))
    }

    func testStrictJSONIsNeverReportedAsCommented() {
        XCTAssertEqual(FormatCanvas.model(from: #"{"a":1}"#).kind, .json)
    }

    func testCommentedBareLiteralIsStillNotJSON() {
        // The object-or-array rule holds across all three kinds.
        XCTAssertFalse(FormatCanvas.model(from: "// note\n42").isValid)
    }

    func testUnterminatedBlockCommentAfterACompleteValueIsAnError() {
        // The value is complete, so nothing else fails: only the unclosed
        // comment makes this invalid. Consuming it as trivia would call this
        // document valid.
        let document = FormatCanvas.model(from: "{\"a\":1}/* never closed")
        XCTAssertFalse(document.isValid)
        XCTAssertEqual(document.errorMessage?.contains("Unterminated block comment"), true)
    }

    func testUnterminatedBlockCommentInsideAValueIsAnError() {
        let document = FormatCanvas.model(from: "{\"a\": 1 /* never closed")
        XCTAssertFalse(document.isValid)
        XCTAssertNotNil(document.errorMessage)
    }

    func testTsconfigShapedFileWithCommentsAndTrailingComma() {
        // The case this whole path exists for: both leniencies at once.
        let document = FormatCanvas.model(from: """
        {
          // options
          "target": "ES2022",
          "strict": true,
        }
        """)
        XCTAssertTrue(document.isValid)
        XCTAssertEqual(document.kind, .jsonc)
        XCTAssertEqual(document.minifiedText, #"{"target":"ES2022","strict":true}"#)
    }

    func testTrailingCommasWithoutComments() {
        let document = FormatCanvas.model(from: #"{"a":[1,2,],}"#)
        XCTAssertTrue(document.isValid)
        XCTAssertEqual(document.kind, .jsonc)
        XCTAssertEqual(document.minifiedText, #"{"a":[1,2]}"#)
    }

    func testStrictJSONStillRejectsTrailingCommas() {
        // The strict reading is unchanged: this is the leniency being opt-in.
        XCTAssertThrowsError(try JSONParser.parse(#"{"a":1,}"#))
        XCTAssertThrowsError(try JSONParser.parse("[1,2,]"))
        XCTAssertEqual(try? JSONParser.parse(#"{"a":1,}"#, options: .jsonc),
                       .object([(key: "a", value: .number("1"))]))
    }

    func testCommentBetweenTheCommaAndTheBrace() {
        // The shape VS Code writes: the comma is not the last thing before the
        // brace, a comment is. Locks the skip between the two.
        let object = FormatCanvas.model(from: """
        {
          "strict": true, // always
        }
        """)
        XCTAssertTrue(object.isValid)
        XCTAssertEqual(object.minifiedText, #"{"strict":true}"#)

        let array = FormatCanvas.model(from: "[\n  1, /* and that is all */\n]")
        XCTAssertTrue(array.isValid)
        XCTAssertEqual(array.minifiedText, "[1]")
    }

    func testJSONLinesRecordsStayStrict() {
        // Documented, not accidental: JSON Lines is one *valid JSON* value per
        // line, so a trailing comma in a record is a bad record — and the error
        // names the line rather than being softened into JSONC.
        let document = FormatCanvas.model(from: "{\"a\":1,}\n{\"b\":2}")
        XCTAssertFalse(document.isValid)
        XCTAssertEqual(document.errorMessage?.contains("line 1"), true)
    }

    func testALoneCommaIsStillAnError() {
        // Leniency is about a comma *after* a value, not commas anywhere.
        XCTAssertFalse(FormatCanvas.model(from: "{,}").isValid)
        XCTAssertFalse(FormatCanvas.model(from: "[,]").isValid)
        XCTAssertFalse(FormatCanvas.model(from: #"{"a":1,,}"#).isValid)
    }

    func testJSONCErrorStillNamesTheRealProblem() {
        // Comments plus something genuinely wrong: the error should not point
        // at the comment that the strict parser tripped over first.
        let document = FormatCanvas.model(from: """
        {
          // options
          "target": ES2022
        }
        """)
        XCTAssertFalse(document.isValid)
        XCTAssertEqual(document.errorMessage?.contains("Unexpected character '/'"), false)
        XCTAssertEqual(document.errorMessage?.contains("line 3"), true)
    }

    func testCommentedDocumentHasASingleValue() {
        let document = FormatCanvas.model(from: "// note\n{\"a\":1}")
        XCTAssertEqual(document.kind, .jsonc)
        // One document, one value — the nil is reserved for JSON Lines.
        XCTAssertEqual(document.value, .object([(key: "a", value: .number("1"))]))
    }

    func testCommentsDoNotSurviveFormatting() {
        // Formatting is driven by the parsed value, so comments are dropped.
        // Documented behaviour, asserted so that it stays deliberate.
        let document = FormatCanvas.model(from: "{\n  // note\n  \"a\": 1\n}")
        XCTAssertEqual(document.kind, .jsonc)
        XCTAssertEqual(document.prettyText?.contains("note"), false)
    }

    // MARK: - JSON Lines

    func testParsesJSONLines() {
        let document = FormatCanvas.model(from: #"{"a":1}\n{"a":2}\n{"a":3}"#.replacingOccurrences(of: "\\n", with: "\n"))
        XCTAssertTrue(document.isValid)
        XCTAssertEqual(document.kind, .lineDelimited)
        XCTAssertEqual(document.recordCount, 3)
        // No single value: JSON Lines is not one document.
        XCTAssertNil(document.value)
    }

    func testJSONLinesRoundTripsThroughCopyMinified() {
        let source = "{\"a\":1}\n{\"b\":[2,3]}"
        let document = FormatCanvas.model(from: source)
        XCTAssertEqual(document.minifiedText, source)
        // Pretty puts a blank line between records so they stay apart once
        // each is expanded.
        XCTAssertEqual(document.prettyText, "{\n  \"a\": 1\n}\n\n{\n  \"b\": [\n    2,\n    3\n  ]\n}")
    }

    func testBlankLinesBetweenRecordsAreIgnored() {
        let document = FormatCanvas.model(from: "{\"a\":1}\n\n\n{\"a\":2}\n")
        XCTAssertEqual(document.recordCount, 2)
    }

    func testSingleDocumentIsNotTreatedAsLines() {
        let document = FormatCanvas.model(from: "{\n  \"a\": 1\n}")
        XCTAssertEqual(document.kind, .json)
        XCTAssertEqual(document.recordCount, 1)
        XCTAssertNotNil(document.value)
    }

    func testOneBadLineReportsThatLineNotTheDocument() {
        let document = FormatCanvas.model(from: "{\"a\":1}\n{\"a\":}\n{\"a\":3}")
        XCTAssertFalse(document.isValid)
        // The document parse fails at line 2 with "trailing content", which
        // says nothing about the record that is actually wrong.
        XCTAssertEqual(document.errorMessage?.contains("trailing"), false)
        XCTAssertEqual(document.errorMessage?.contains("line 2"), true)
    }

    func testMixedRecordKindsAreStillJSONLines() {
        // First char `{`, last char `]`: the whole-buffer shape check fails, so
        // this only works if the line reader is consulted anyway.
        let document = FormatCanvas.model(from: "{\"a\":1}\n[1,2,3]")
        XCTAssertTrue(document.isValid)
        XCTAssertEqual(document.kind, .lineDelimited)
        XCTAssertEqual(document.recordCount, 2)
    }

    func testBrokenDocumentKeepsItsOwnError() {
        // Lines that do not each look like JSON: this was a document with a
        // typo, so the document's error is the useful one. A missing comma,
        // since a spare one is now accepted as JSONC.
        let document = FormatCanvas.model(from: "{\n  \"a\": 1\n  \"b\": 2\n}")
        XCTAssertFalse(document.isValid)
        XCTAssertEqual(document.errorMessage?.contains("line 3"), true)
    }

    func testBareLiteralLinesAreNotJSONLines() {
        XCTAssertFalse(FormatCanvas.model(from: "42\n43\n44").isValid)
    }

    func testJSONLinesTokensCarryEveryRecord() {
        let document = FormatCanvas.model(from: "{\"a\":1}\n{\"a\":2}")
        let rendered = document.tokens.map(\.text).joined()
        XCTAssertTrue(rendered.contains("\"a\": 1"))
        XCTAssertTrue(rendered.contains("\"a\": 2"))
    }

    func testReadsWholeFileRatherThanALeadingSlice() throws {
        // Regression: the Quick Look extension used to parse the first 8 MB of
        // a file, so any larger file — however valid — came back "Not JSON".
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipformat-large-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let entries = Array(repeating: #"{"k":"0123456789"}"#, count: 500_000).joined(separator: ",")
        try Data(("[" + entries + "]").utf8).write(to: url)
        XCTAssertGreaterThan(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 8 * 1024 * 1024)

        let document = try FormatCanvas.model(contentsOf: url)
        XCTAssertTrue(document.isValid)
        XCTAssertNil(document.errorMessage)
    }

    func testFileOverTheLimitIsRefusedBySizeNotCalledInvalid() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipformat-over-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"a":1,"b":2}"#.utf8).write(to: url)

        let document = try FormatCanvas.model(contentsOf: url, byteLimit: 4)
        XCTAssertFalse(document.isValid)
        XCTAssertEqual(document.errorTitle, "Too large")
        XCTAssertTrue(document.errorMessage?.contains("limit") == true)
        // The badge must not blame the file for being malformed.
        let html = FormatCanvas.html(from: document, appearance: .light)
        XCTAssertTrue(html.contains(">Too large<"))
        XCTAssertFalse(html.contains(">Not JSON<"))
    }

    func testTruncationAppendsNotice() {
        let tokens = PrettyPrinter.tokens(for: .array(Array(repeating: .number("1"), count: 200)), indent: 2)
        let truncated = FormatCanvas.truncate(tokens, toCharacters: 40)
        XCTAssertTrue(truncated.map(\.text).joined().hasSuffix("… truncated"))
        XCTAssertLessThan(truncated.count, tokens.count)
    }

    func testOversizedDocumentTruncatesFormattedOutput() {
        let big = "[" + Array(repeating: "\"0123456789\"", count: 60_000).joined(separator: ",") + "]"
        let document = FormatCanvas.model(from: big)
        XCTAssertTrue(document.isValid)
        XCTAssertTrue(document.isTruncated)
        let rendered = document.tokens.map(\.text).joined()
        XCTAssertLessThan(rendered.count, FormatCanvas.renderCharacterLimit + 100)
        XCTAssertTrue(rendered.hasSuffix("… truncated"))
        // The full text is still available for Copy Pretty.
        XCTAssertGreaterThan(document.prettyText?.count ?? 0, FormatCanvas.renderCharacterLimit)
    }

    func testHTMLUsesRequestedFontSizeAndTabSize() {
        let document = FormatCanvas.model(from: #"{"a":1}"#, indent: 4)
        let html = FormatCanvas.html(from: document, appearance: .light, fontSize: 18)
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
        let html = FormatCanvas.html(from: FormatCanvas.model(from: #"{"a":"b"}"#), appearance: .light)
        // Key, ':' and value each get one span; whitespace and newlines stay bare.
        XCTAssertTrue(html.contains(#"<span class="k">&quot;a&quot;</span><span class="p">:</span> <span class="s">&quot;b&quot;</span>"#))
        XCTAssertEqual(html.components(separatedBy: "<span").count - 1, 5)
    }

    func testDeepNestingIsRejectedNotCrashed() {
        let deep = String(repeating: "[", count: 5_000) + String(repeating: "]", count: 5_000)
        XCTAssertFalse(FormatCanvas.model(from: deep).isValid)
    }
}
