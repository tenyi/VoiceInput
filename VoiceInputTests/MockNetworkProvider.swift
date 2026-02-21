import Foundation
@testable import VoiceInput

class MockNetworkProvider: NetworkProviderProtocol {
    var mockData: Data?
    var mockResponse: URLResponse?
    var mockError: Error?
    
    var requestsReceived: [URLRequest] = []
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestsReceived.append(request)
        
        if let error = mockError {
            throw error
        }
        
        let data = mockData ?? Data()
        let response = mockResponse ?? HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        
        return (data, response)
    }
}
