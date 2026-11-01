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
    ///   - session: A custom `URLSession` for the transport — e.g. one whose configuration
    ///     carries `connectionProxyDictionary` to route through a proxy. `nil` uses the
    ///     transport's default session. Configure the session fully before passing it (the
    ///     proxy dictionary lives on its configuration); the caller keeps the session's
    ///     lifecycle — the transport retains it, invalidation stays yours.
    init(
        token: String,
        hostname: String = "gitlab.com",
        bodyLoggingPolicy: BodyLoggingPolicy = .never,
        session: URLSession? = nil
    ) throws {
        try self.init(
            serverURL: Servers.Server1.url(hostname: hostname),
            configuration: Configuration(dateTranscoder: GitLabDateTranscoder()),
            transport: Self.makeTransport(session: session),
            middlewares: [
                HeaderMiddleware(bearerToken: token),
                OSLogLoggingMiddleware(bodyLoggingConfiguration: bodyLoggingPolicy),
            ]
        )
    }

    /// Creates a GitLab REST API client pointed at an explicit server URL.
    ///
    /// Use this for self-managed instances that aren't reachable as `https://{hostname}` —
    /// e.g. an HTTP-only or non-standard-port host such as `http://git.example.lab`. The
    /// ``init(token:hostname:bodyLoggingPolicy:session:)`` convenience always builds an `https://`
    /// URL from the spec's server template; this initializer takes the root URL verbatim.
    ///
    /// - Parameters:
    ///   - token: A GitLab Personal/Project/Group Access Token (or OAuth2 access token),
    ///     sent as `Authorization: Bearer <token>`.
    ///   - serverURL: The API **root** (scheme + host [+ port]) only, e.g.
    ///     `URL(string: "http://git.example.lab")!`. The generated operations append the
    ///     `/api/v4/...` path themselves, matching the spec's `https://{hostname}` server.
    ///   - bodyLoggingPolicy: How much of request/response bodies to log via OSLog.
    ///     Defaults to `.never`; use `.upTo(maxBytes:)` while debugging.
    ///   - session: A custom `URLSession` for the transport — e.g. one whose configuration
    ///     carries `connectionProxyDictionary` to route through a proxy. `nil` uses the
    ///     transport's default session. Configure the session fully before passing it (the
    ///     proxy dictionary lives on its configuration); the caller keeps the session's
    ///     lifecycle — the transport retains it, invalidation stays yours.
    init(
        token: String,
        serverURL: URL,
        bodyLoggingPolicy: BodyLoggingPolicy = .never,
        session: URLSession? = nil
    ) {
        self.init(
            serverURL: serverURL,
            configuration: Configuration(dateTranscoder: GitLabDateTranscoder()),
            transport: Self.makeTransport(session: session),
            middlewares: [
                HeaderMiddleware(bearerToken: token),
                OSLogLoggingMiddleware(bodyLoggingConfiguration: bodyLoggingPolicy),
            ]
        )
    }

    /// A shared session is the default; a caller-provided session becomes the transport's
    /// (proxy-aware configurations, pinned delegates, test doubles). Internal — the test
    /// target asserts the session actually lands on the transport.
    static func makeTransport(session: URLSession?) -> URLSessionTransport {
        guard let session else { return URLSessionTransport() }
        return URLSessionTransport(configuration: .init(session: session))
    }
}
