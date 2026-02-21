import Foundation

/// 網路層協定，用於分離 URLSession 進行 Mock 測試
protocol NetworkProviderProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: NetworkProviderProtocol {}
