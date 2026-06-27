import Foundation
import HTTPTypes
import OpenAPIRuntime

/// A client middleware that injects a fixed value into a header field of every request.
///
/// Synthesized from the header-injection middlewares across the author's OpenAPI clients
/// — `SwiftOpenAPIGenMiddlewares/HeaderMiddleware`, `YooMoneyAPIClient.HeaderMiddleware`,
/// `YandexDeliveryExpress.AuthMiddleware` — keeping the shared core (typed field + value,
/// two convenience inits) and dropping per-API cruft: the `Idempotence-Key` header
/// (payment-specific, author-flagged "temporary") and a forced `Content-Type`
/// (the generator already sets content types per operation). The `httpFieldname`
/// typo is fixed, and a `bearerToken:` convenience is added for the common case.
///
/// For GitLab this carries the static credential: a Personal/Project/Group Access Token
/// is sent as `Authorization: Bearer <token>`, matching the spec's `http` bearer scheme.
/// (GitLab also accepts the same token via `PRIVATE-TOKEN`; use the field-name init.)
///
/// For an *expiring* OAuth2 access token, use `RefreshTokenAuthMiddleware`
/// (https://github.com/laconicman/RefreshTokenAuthMiddleware) with a `SignInAndRefresh`
/// conformance driving GitLab's `/oauth/token`, instead of this static injector.
public struct HeaderMiddleware: Sendable {
    private let httpFieldName: HTTPField.Name
    private let value: String

    /// Sets `Authorization: Bearer <token>` — the common bearer / access-token case.
    public init(bearerToken token: String) {
        self.httpFieldName = .authorization
        self.value = "Bearer \(token)"
    }

    /// Sets `Authorization: <value>` verbatim (e.g. `"Basic …"`, `"Bearer …"`).
    public init(authorizationHeaderFieldValue value: String) {
        self.httpFieldName = .authorization
        self.value = value
    }

    /// Sets an arbitrary header field (e.g. `PRIVATE-TOKEN`).
    public init(fieldName: HTTPField.Name, value: String) {
        self.httpFieldName = fieldName
        self.value = value
    }
}

extension HeaderMiddleware: ClientMiddleware {
    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[httpFieldName] = value
        return try await next(request, body, baseURL)
    }
}
