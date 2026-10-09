import XCTest
@testable import VoiceInput

/// 測試提示詞組合、逐字稿協定與 App 風格對應
final class LLMPromptBuilderTests: XCTestCase {

    // MARK: - buildSystemPrompt

    /// general 且無詞彙時應原樣回傳 base
    func test_build_generalWithoutVocabularyReturnsBase() {
        XCTAssertEqual(LLMPromptBuilder.buildSystemPrompt(base: "BASE", style: .general, vocabulary: []), "BASE")
    }

    /// 組合順序：base → 風格 → 詞彙
    func test_build_ordersSections() throws {
        let result = LLMPromptBuilder.buildSystemPrompt(base: "BASE", style: .chat, vocabulary: ["VoiceInput"])
        let styleText = try XCTUnwrap(LLMContextStyle.chat.instruction)
        let baseRange = try XCTUnwrap(result.range(of: "BASE"))
        let styleRange = try XCTUnwrap(result.range(of: styleText))
        let vocabRange = try XCTUnwrap(result.range(of: "VoiceInput"))
        XCTAssertLessThan(baseRange.lowerBound, styleRange.lowerBound)
        XCTAssertLessThan(styleRange.lowerBound, vocabRange.lowerBound)
    }

    /// 詞彙超過上限時只取前 vocabularyLimit 個
    func test_build_capsVocabulary() {
        let terms = (0..<60).map { "詞\($0)號" }
        let result = LLMPromptBuilder.buildSystemPrompt(base: "B", style: .general, vocabulary: terms)
        XCTAssertTrue(result.contains("詞49號"))
        XCTAssertFalse(result.contains("詞50號"))
    }

    // MARK: - 逐字稿協定

    /// 協定附加於末端並保留原 prompt
    func test_applyTranscriptProtocol_appendsAfterPrompt() {
        let result = LLMPromptBuilder.applyTranscriptProtocol(to: "BASE")
        XCTAssertTrue(result.hasPrefix("BASE"))
        XCTAssertTrue(result.contains("<transcript>"))
    }

    /// 以標籤包裝逐字稿
    func test_wrapTranscript() {
        XCTAssertEqual(LLMPromptBuilder.wrapTranscript("你好"), "<transcript>\n你好\n</transcript>")
    }

    /// 清理回顯的標籤與空白
    func test_sanitizeOutput_removesEchoedTags() {
        XCTAssertEqual(LLMPromptBuilder.sanitizeOutput("<transcript>\n你好。\n</transcript>\n"), "你好。")
        XCTAssertEqual(LLMPromptBuilder.sanitizeOutput("你好。"), "你好。")
    }

    // MARK: - AppContextResolver

    /// 已知 bundle ID 對應正確風格
    func test_resolver_knownBundleIDs() {
        XCTAssertEqual(AppContextResolver.style(forBundleID: "com.tinyspeck.slackmacgap"), .chat)
        XCTAssertEqual(AppContextResolver.style(forBundleID: "com.apple.mail"), .email)
        XCTAssertEqual(AppContextResolver.style(forBundleID: "com.apple.dt.Xcode"), .code)
    }

    /// nil 或未知 bundle ID 回退為 general
    func test_resolver_unknownOrNilFallsBackToGeneral() {
        XCTAssertEqual(AppContextResolver.style(forBundleID: nil), .general)
        XCTAssertEqual(AppContextResolver.style(forBundleID: "com.apple.Safari"), .general)
    }
}
