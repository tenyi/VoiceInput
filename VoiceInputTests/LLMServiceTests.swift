import Foundation
import XCTest
@testable import VoiceInput

/// 測試 LLMService:四個 provider、URL 正規化、錯誤處理、ThinkTag 過濾。
/// 透過 MockNetworkProvider 注入可控的 HTTP 回應。
final class LLMServiceTests: XCTestCase {

    // MARK: - URL 正規化

    /// 既有 https scheme 應原樣保留
    func test_normalizeURL_keepsHttpsScheme() {
        let service = LLMService()
        XCTAssertEqual(service.normalizeURLForTesting("https://api.openai.com"), "https://api.openai.com")
    }

    /// 既有 http scheme 應原樣保留
    func test_normalizeURL_keepsHttpScheme() {
        let service = LLMService()
        XCTAssertEqual(service.normalizeURLForTesting("http://example.com"), "http://example.com")
    }

    /// localhost 自動補 http
    func test_normalizeURL_addsHttpForLocalhost() {
        let service = LLMService()
        XCTAssertEqual(service.normalizeURLForTesting("localhost:11434"), "http://localhost:11434")
    }

    /// 127.0.0.1 自動補 http
    func test_normalizeURL_addsHttpForLoopback() {
        let service = LLMService()
        XCTAssertEqual(service.normalizeURLForTesting("127.0.0.1:11434"), "http://127.0.0.1:11434")
    }

    /// 連續 port localhost 變體也應自動補 http
    func test_normalizeURL_addsHttpForMdnsLocal() {
        let service = LLMService()
        XCTAssertEqual(service.normalizeURLForTesting("localhost:8080"), "http://localhost:8080")
    }

    /// RFC1918 私有網段自動補 http
    func test_normalizeURL_addsHttpForPrivateNetwork() {
        let service = LLMService()
        XCTAssertEqual(service.normalizeURLForTesting("192.168.1.10:11434"), "http://192.168.1.10:11434")
        XCTAssertEqual(service.normalizeURLForTesting("10.0.0.5:11434"), "http://10.0.0.5:11434")
        XCTAssertEqual(service.normalizeURLForTesting("172.16.0.1:11434"), "http://172.16.0.1:11434")
        XCTAssertEqual(service.normalizeURLForTesting("172.31.255.255:11434"), "http://172.31.255.255:11434")
    }

    /// 公有網域預設走 https
    func test_normalizeURL_usesHttpsForPublicDomain() {
        let service = LLMService()
        XCTAssertEqual(service.normalizeURLForTesting("api.openai.com"), "https://api.openai.com")
        XCTAssertEqual(service.normalizeURLForTesting("api.anthropic.com"), "https://api.anthropic.com")
    }

    /// 172.x 不在 RFC1918 範圍 (16-31) 內時走 https
    func test_normalizeURL_172OutsidePrivateRangeUsesHttps() {
        let service = LLMService()
        XCTAssertEqual(service.normalizeURLForTesting("172.15.0.1:8080"), "https://172.15.0.1:8080")
        XCTAssertEqual(service.normalizeURLForTesting("172.32.0.1:8080"), "https://172.32.0.1:8080")
    }

    /// 頭尾空白應被去除
    func test_normalizeURL_trimsWhitespace() {
        let service = LLMService()
        XCTAssertEqual(service.normalizeURLForTesting("  http://api.openai.com  "), "http://api.openai.com")
    }

    // MARK: - correctText 輸入驗證

    /// 空字串應拋出 invalidConfiguration
    func test_correctText_emptyStringThrows() async {
        let service = LLMService()
        await assertThrowsLLMError(
            try await service.correctText(
                text: "", prompt: "p", provider: .openAI, apiKey: "k", url: "", model: "m"
            ),
            .invalidConfiguration
        )
    }

    /// OpenAI 缺 apiKey 應拋出 invalidConfiguration
    func test_correctText_openAI_missingApiKeyThrows() async {
        let service = LLMService(networkProvider: MockNetworkProvider())
        await assertThrowsLLMError(
            try await service.correctText(
                text: "hi", prompt: "p", provider: .openAI, apiKey: "", url: "", model: "gpt-4o-mini"
            ),
            .invalidConfiguration
        )
    }

    /// Anthropic 缺 apiKey 應拋出 invalidConfiguration
    func test_correctText_anthropic_missingApiKeyThrows() async {
        let service = LLMService(networkProvider: MockNetworkProvider())
        await assertThrowsLLMError(
            try await service.correctText(
                text: "hi", prompt: "p", provider: .anthropic, apiKey: "", url: "", model: "claude-3-haiku-20240307"
            ),
            .invalidConfiguration
        )
    }

    // MARK: - OpenAI provider

    /// OpenAI 200 成功回應,驗證 header 與 URL
    func test_openAI_successResponse() async throws {
        let mock = self.makeMock(data: openAISuccessBody(text: "修正後的文字"), statusCode: 200)
        let service = LLMService(networkProvider: mock)

        let result = try await service.correctText(
            text: "原文", prompt: "請修正", provider: .openAI,
            apiKey: "sk-test", url: "", model: "gpt-4o-mini"
        )

        XCTAssertEqual(result, "修正後的文字")
        let request = try XCTUnwrap(mock.requestsReceived.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(request.url?.absoluteString.contains("api.openai.com") ?? false)
    }

    /// OpenAI 預設 model 為 gpt-4o-mini
    func test_openAI_defaultModel() async throws {
        let mock = self.makeMock(data: openAISuccessBody(text: "ok"), statusCode: 200)
        let service = LLMService(networkProvider: mock)

        _ = try await service.correctText(
            text: "hi", prompt: "p", provider: .openAI, apiKey: "sk-test", url: "", model: ""
        )

        let body = try XCTUnwrap(mock.requestsReceived.first?.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-4o-mini")
    }

    /// OpenAI 401 應拋出 httpError,body 解析為 message 欄位
    func test_openAI_401ThrowsHttpError() async {
        let mock = self.makeMock(
            data: #"{"error":{"message":"Invalid API key"}}"#.data(using: .utf8)!,
            statusCode: 401
        )
        let service = LLMService(networkProvider: mock)

        do {
            _ = try await service.correctText(
                text: "hi", prompt: "p", provider: .openAI, apiKey: "bad", url: "", model: "gpt-4o-mini"
            )
            XCTFail("應拋出錯誤")
        } catch let LLMServiceError.httpError(statusCode, body) {
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(body, "Invalid API key")
        } catch {
            XCTFail("預期 .httpError,實際為 \(error)")
        }
    }

    /// OpenAI 429 額度錯誤
    func test_openAI_429RateLimit() async {
        let mock = self.makeMock(
            data: #"{"error":{"message":"Rate limit"}}"#.data(using: .utf8)!,
            statusCode: 429
        )
        let service = LLMService(networkProvider: mock)

        await assertThrowsLLMError(
            try await service.correctText(
                text: "hi", prompt: "p", provider: .openAI, apiKey: "k", url: "", model: "gpt-4o-mini"
            ),
            .httpError
        )
    }

    /// OpenAI 500 伺服器錯誤
    func test_openAI_500ServerError() async {
        let mock = self.makeMock(data: Data(), statusCode: 500)
        let service = LLMService(networkProvider: mock)

        await assertThrowsLLMError(
            try await service.correctText(
                text: "hi", prompt: "p", provider: .openAI, apiKey: "k", url: "", model: "gpt-4o-mini"
            ),
            .httpError
        )
    }

    /// OpenAI 200 但回應 body 含 error 欄位 → apiError
    func test_openAI_responseErrorFieldThrowsApiError() async {
        let mock = self.makeMock(
            data: #"{"error":{"message":"context_length_exceeded"}}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let service = LLMService(networkProvider: mock)

        do {
            _ = try await service.correctText(
                text: "hi", prompt: "p", provider: .openAI, apiKey: "k", url: "", model: "gpt-4o-mini"
            )
            XCTFail("應拋出錯誤")
        } catch let LLMServiceError.apiError(msg) {
            XCTAssertEqual(msg, "context_length_exceeded")
        } catch {
            XCTFail("預期 .apiError,實際為 \(error)")
        }
    }

    /// OpenAI 200 但格式不正確 → invalidResponse
    func test_openAI_malformedJSONThrowsInvalidResponse() async {
        let mock = self.makeMock(
            data: #"{"unrelated":"data"}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let service = LLMService(networkProvider: mock)

        await assertThrowsLLMError(
            try await service.correctText(
                text: "hi", prompt: "p", provider: .openAI, apiKey: "k", url: "", model: "gpt-4o-mini"
            ),
            .invalidResponse
        )
    }

    /// <think>...</think> 標籤應被過濾
    func test_openAI_stripThinkTags() async throws {
        let mock = self.makeMock(
            data: openAISuccessBody(text: "<think>這是思考過程</think>實際結果"),
            statusCode: 200
        )
        let service = LLMService(networkProvider: mock)

        let result = try await service.correctText(
            text: "hi", prompt: "p", provider: .openAI, apiKey: "k", url: "", model: "gpt-4o-mini"
        )
        XCTAssertEqual(result, "實際結果")
    }

    // MARK: - Anthropic provider

    /// Anthropic 200 成功,驗證 x-api-key 與 anthropic-version header
    func test_anthropic_successResponse() async throws {
        let mock = self.makeMock(data: anthropicSuccessBody(text: "修正後"), statusCode: 200)
        let service = LLMService(networkProvider: mock)

        let result = try await service.correctText(
            text: "原文", prompt: "請修正", provider: .anthropic,
            apiKey: "sk-ant", url: "", model: "claude-3-haiku-20240307"
        )

        XCTAssertEqual(result, "修正後")
        let request = try XCTUnwrap(mock.requestsReceived.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    /// Anthropic 預設 model 與 max_tokens
    func test_anthropic_defaultModel() async throws {
        let mock = self.makeMock(data: anthropicSuccessBody(text: "ok"), statusCode: 200)
        let service = LLMService(networkProvider: mock)

        _ = try await service.correctText(
            text: "hi", prompt: "p", provider: .anthropic, apiKey: "sk-ant", url: "", model: ""
        )

        let body = try XCTUnwrap(mock.requestsReceived.first?.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "claude-3-haiku-20240307")
        XCTAssertEqual(json["max_tokens"] as? Int, 1024)
    }

    /// Anthropic 格式錯誤 → invalidResponse
    func test_anthropic_malformedThrowsInvalidResponse() async {
        let mock = self.makeMock(
            data: #"{"unrelated":"data"}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let service = LLMService(networkProvider: mock)

        await assertThrowsLLMError(
            try await service.correctText(
                text: "hi", prompt: "p", provider: .anthropic, apiKey: "k", url: "", model: "m"
            ),
            .invalidResponse
        )
    }

    // MARK: - Ollama provider

    /// Ollama 預設 URL 為 http://localhost:11434/v1/chat/completions
    func test_ollama_defaultURL() async throws {
        let mock = MockNetworkProvider()
        mock.mockData = openAISuccessBody(text: "ok")
        mock.mockResponse = HTTPURLResponse(
            url: URL(string: "http://localhost:11434/v1/chat/completions")!,
            statusCode: 200, httpVersion: nil, headerFields: nil
        )
        let service = LLMService(networkProvider: mock)

        _ = try await service.correctText(
            text: "hi", prompt: "p", provider: .ollama, apiKey: "", url: "", model: "llama3"
        )

        let request = try XCTUnwrap(mock.requestsReceived.first)
        XCTAssertTrue(request.url?.absoluteString.contains("localhost:11434") ?? false)
        XCTAssertTrue(request.url?.absoluteString.contains("/v1/chat/completions") ?? false)
    }

    /// Ollama 原生端點 /api/chat 不應被拼接 /v1
    func test_ollama_nativeEndpointNotMangled() async throws {
        let mock = MockNetworkProvider()
        mock.mockData = openAISuccessBody(text: "ok")
        mock.mockResponse = HTTPURLResponse(
            url: URL(string: "http://localhost:11434/api/chat")!,
            statusCode: 200, httpVersion: nil, headerFields: nil
        )
        let service = LLMService(networkProvider: mock)

        _ = try await service.correctText(
            text: "hi", prompt: "p", provider: .ollama, apiKey: "",
            url: "http://localhost:11434/api/chat", model: "llama3"
        )

        let request = try XCTUnwrap(mock.requestsReceived.first)
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/chat")
    }

    /// Ollama 私有網段自動補 http
    func test_ollama_privateNetworkAutoHttp() async throws {
        let mock = MockNetworkProvider()
        mock.mockData = openAISuccessBody(text: "ok")
        mock.mockResponse = HTTPURLResponse(
            url: URL(string: "http://192.168.1.10:11434/v1/chat/completions")!,
            statusCode: 200, httpVersion: nil, headerFields: nil
        )
        let service = LLMService(networkProvider: mock)

        _ = try await service.correctText(
            text: "hi", prompt: "p", provider: .ollama, apiKey: "",
            url: "192.168.1.10:11434", model: "llama3"
        )

        let request = try XCTUnwrap(mock.requestsReceived.first)
        XCTAssertEqual(request.url?.scheme, "http")
        XCTAssertTrue(request.url?.absoluteString.contains("192.168.1.10") ?? false)
    }

    /// Ollama 尾斜線應被去除,避免 //v1 雙斜線
    func test_ollama_trailingSlashHandled() async throws {
        let mock = MockNetworkProvider()
        mock.mockData = openAISuccessBody(text: "ok")
        mock.mockResponse = HTTPURLResponse(
            url: URL(string: "http://localhost:11434/v1/chat/completions")!,
            statusCode: 200, httpVersion: nil, headerFields: nil
        )
        let service = LLMService(networkProvider: mock)

        _ = try await service.correctText(
            text: "hi", prompt: "p", provider: .ollama, apiKey: "",
            url: "http://localhost:11434/", model: "llama3"
        )

        let request = try XCTUnwrap(mock.requestsReceived.first)
        XCTAssertFalse(request.url?.absoluteString.contains("//v1") ?? false)
    }

    // MARK: - Custom provider

    /// Custom 缺 url → invalidConfiguration
    func test_custom_missingURLThrows() async {
        let service = LLMService(networkProvider: MockNetworkProvider())
        await assertThrowsLLMError(
            try await service.correctText(
                text: "hi", prompt: "p", provider: .custom, apiKey: "k", url: "", model: "m"
            ),
            .invalidConfiguration
        )
    }

    /// Custom 無 apiKey → 不送 Authorization header
    func test_custom_noAPIKeyOmitsAuthorization() async throws {
        let mock = self.makeMock(data: openAISuccessBody(text: "ok"), statusCode: 200)
        let service = LLMService(networkProvider: mock)

        _ = try await service.correctText(
            text: "hi", prompt: "p", provider: .custom, apiKey: "",
            url: "https://api.example.com/v1/chat/completions", model: "custom-model"
        )

        let request = try XCTUnwrap(mock.requestsReceived.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    /// Custom 有 apiKey → 加上 Bearer prefix
    func test_custom_apiKeyAddsBearer() async throws {
        let mock = self.makeMock(data: openAISuccessBody(text: "ok"), statusCode: 200)
        let service = LLMService(networkProvider: mock)

        _ = try await service.correctText(
            text: "hi", prompt: "p", provider: .custom, apiKey: "secret",
            url: "https://api.example.com/v1/chat/completions", model: "custom-model"
        )

        let request = try XCTUnwrap(mock.requestsReceived.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    /// Custom model 為空 → 不送 model 欄位
    func test_custom_emptyModelOmitsField() async throws {
        let mock = self.makeMock(data: openAISuccessBody(text: "ok"), statusCode: 200)
        let service = LLMService(networkProvider: mock)

        _ = try await service.correctText(
            text: "hi", prompt: "p", provider: .custom, apiKey: "k",
            url: "https://api.example.com/v1/chat/completions", model: ""
        )

        let body = try XCTUnwrap(mock.requestsReceived.first?.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["model"])
    }

    // MARK: - 網路錯誤

    /// 底層拋出 Error 應被包成 networkError
    func test_networkErrorWrappedAsLLMError() async {
        let mock = MockNetworkProvider()
        struct TestError: LocalizedError { var errorDescription: String? { "boom" } }
        mock.mockError = TestError()
        let service = LLMService(networkProvider: mock)

        do {
            _ = try await service.correctText(
                text: "hi", prompt: "p", provider: .openAI, apiKey: "k", url: "", model: "gpt-4o-mini"
            )
            XCTFail("應拋出錯誤")
        } catch let LLMServiceError.networkError(err) {
            XCTAssertNotNil(err)
        } catch {
            XCTFail("預期 .networkError,實際為 \(error)")
        }
    }

    // MARK: - 錯誤訊息內容

    /// 401 中文提示應包含「認證」
    func test_errorDescription_401() {
        let err = LLMServiceError.httpError(statusCode: 401, body: nil)
        XCTAssertTrue(err.errorDescription?.contains("認證") ?? false)
    }

    /// 404 中文提示應包含「端點」
    func test_errorDescription_404() {
        let err = LLMServiceError.httpError(statusCode: 404, body: nil)
        XCTAssertTrue(err.errorDescription?.contains("端點") ?? false)
    }

    /// 429 中文提示應包含「額度」
    func test_errorDescription_429() {
        let err = LLMServiceError.httpError(statusCode: 429, body: nil)
        XCTAssertTrue(err.errorDescription?.contains("額度") ?? false)
    }

    /// 5xx 中文提示應包含「伺服器」
    func test_errorDescription_5xx() {
        for code in [500, 502, 503, 599] {
            let err = LLMServiceError.httpError(statusCode: code, body: nil)
            XCTAssertTrue(err.errorDescription?.contains("伺服器") ?? false, "statusCode \(code) 應有伺服器提示")
        }
    }

    /// body 內容應出現在錯誤描述中
    func test_errorDescription_httpErrorBodyIncluded() {
        let err = LLMServiceError.httpError(statusCode: 400, body: "bad input")
        XCTAssertTrue(err.errorDescription?.contains("bad input") ?? false)
    }

    // MARK: - Helpers

    private func makeMock(data: Data, statusCode: Int) -> MockNetworkProvider {
        let mock = MockNetworkProvider()
        mock.mockData = data
        mock.mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )
        return mock
    }

    private func openAISuccessBody(text: String) -> Data {
        let json: [String: Any] = [
            "choices": [[
                "message": ["content": text],
                "index": 0
            ]]
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func anthropicSuccessBody(text: String) -> Data {
        let json: [String: Any] = [
            "content": [[
                "type": "text",
                "text": text
            ]]
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    /// 斷言一個拋出 LLMServiceError 的 async 表達式匹配指定的 case 種類
    private func assertThrowsLLMError(
        _ expression: @autoclosure () async throws -> some Any,
        _ expectedCase: LLMErrorCase,
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("應拋出錯誤", file: file, line: line)
        } catch let error as LLMServiceError {
            XCTAssertTrue(
                expectedCase.matches(error),
                "預期 \(expectedCase),實際為 \(error)",
                file: file, line: line
            )
        } catch {
            XCTFail("預期 LLMServiceError,實際為 \(error)", file: file, line: line)
        }
    }
}

/// 測試用:用 case 種類比對,不需列舉具體 payload
enum LLMErrorCase {
    case invalidConfiguration
    case invalidResponse
    case networkError
    case apiError
    case noContent
    case httpError

    func matches(_ error: LLMServiceError) -> Bool {
        switch (self, error) {
        case (.invalidConfiguration, .invalidConfiguration),
             (.invalidResponse, .invalidResponse),
             (.networkError, .networkError),
             (.apiError, .apiError),
             (.noContent, .noContent),
             (.httpError, .httpError):
            return true
        default:
            return false
        }
    }
}
