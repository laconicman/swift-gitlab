import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import OSLogLoggingMiddleware
import GitLabOpenAPI

public extension Client {
    /// Creates a GitLab REST API client authenticated with an access token.
    ///
    /// Mirrors the construction pattern of `YooMoneyAPIClient`: a static auth header
    /// (`HeaderMiddleware`) plus `OSLogLoggingMiddleware`, over `URLSessionTransport`.
    ///
    /// - Parameters:
    ///   - token: A GitLab Personal/Project/Group Access Token (or OAuth2 access token).
    ///     Sent as `Authorization: Bearer <token>`, matching the spec's `http` bearer scheme.
    ///   - hostname: The GitLab instance host. Defaults to `gitlab.com`; pass your own
    ///     (e.g. `gitlab.example.com`) for a self-managed instance — the spec models the
    ///     server as `https://{hostname}`.
    ///   - bodyLoggingPolicy: How much of request/response bodies to log via OSLog.
    ///     Defaults to `.never`; use `.upTo(maxBytes:)` while debugging.
    init(
        token: String,
        hostname: String = "gitlab.com",
        bodyLoggingPolicy: BodyLoggingPolicy = .never
    ) throws {
        try self.init(
            serverURL: Servers.Server1.url(hostname: hostname),
            configuration: Configuration(dateTranscoder: GitLabDateTranscoder()),
            transport: URLSessionTransport(),
            middlewares: [
                HeaderMiddleware(bearerToken: token),
                OSLogLoggingMiddleware(bodyLoggingConfiguration: bodyLoggingPolicy),
            ]
        )
    }
}
