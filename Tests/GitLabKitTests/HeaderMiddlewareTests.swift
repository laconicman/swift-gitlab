import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import GitLabKit

/// Captures a request across the `@Sendable` middleware boundary without a data race.
private actor RequestBox {
    private(set) var request: HTTPRequest?
    func set(_ request: HTTPRequest) { self.request = request }
}

@Suite("HeaderMiddleware")
struct HeaderMiddlewareTests {

    private func capturedRequest(
        from middleware: HeaderMiddleware
    ) async throws -> HTTPRequest {
        let box = RequestBox()
        let request = HTTPRequest(method: .get, scheme: "https", authority: "gitlab.com", path: "/api/v4/user")
        _ = try await middleware.intercept(
            request,
            body: nil,
            baseURL: URL(string: "https://gitlab.com")!,
            operationID: "getApiV4User"
        ) { req, body, _ in
            await box.set(req)
            return (HTTPResponse(status: .ok), body)
        }
        return try #require(await box.request)
    }

    @Test("bearerToken sets Authorization: Bearer")
    func injectsBearer() async throws {
        let req = try await capturedRequest(from: HeaderMiddleware(bearerToken: "glpat-secret"))
        #expect(req.headerFields[.authorization] == "Bearer glpat-secret")
    }

    @Test("authorizationHeaderFieldValue is set verbatim")
    func injectsVerbatim() async throws {
        let req = try await capturedRequest(from: HeaderMiddleware(authorizationHeaderFieldValue: "Bearer glpat-secret"))
        #expect(req.headerFields[.authorization] == "Bearer glpat-secret")
    }

    @Test("supports a custom PRIVATE-TOKEN field")
    func injectsPrivateToken() async throws {
        let field = try #require(HTTPField.Name("PRIVATE-TOKEN"))
        let req = try await capturedRequest(from: HeaderMiddleware(fieldName: field, value: "glpat-secret"))
        #expect(req.headerFields[field] == "glpat-secret")
    }
}
