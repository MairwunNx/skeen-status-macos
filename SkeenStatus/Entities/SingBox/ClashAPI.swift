import Alamofire
import ComposableArchitecture
import Foundation

/// Where sing-box's Clash API listens and the secret it wants.
struct ClashEndpoint: Equatable, Sendable {
    var baseURL: URL
    var secret: String
}

extension ClashEndpoint {
    /// The endpoint the config points at, or nil when the API is off.
    init?(config: Config, secret: String?) {
        guard let url = config.clashAPIBaseURL else { return nil }
        self.init(baseURL: url, secret: secret ?? "")
    }
}

struct ClashProxy: Decodable, Equatable, Sendable {
    var type: String
    var name: String
    var now: String?
    var all: [String]?
}

private struct ClashVersionDTO: Decodable {
    var version: String
}

private struct ClashConfigsDTO: Decodable {
    var mode: String
    var modeList: [String]?

    enum CodingKeys: String, CodingKey {
        case mode
        case modeList = "mode-list"
    }
}

private struct ClashProxiesDTO: Decodable {
    var proxies: [String: ClashProxy]
}

private struct ClashConnectionsDTO: Decodable {
    struct Connection: Decodable {
        var download: Int64?
        var upload: Int64?
    }
    var downloadTotal: Int64
    var uploadTotal: Int64
    var memory: Int64?
    var connections: [Connection]?
}

enum ClashAPIError: Error, Equatable, LocalizedError {
    case unauthorized
    case unreachable(String)
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Clash API не принял секрет"
        case .unreachable(let reason): return "Clash API недоступен: \(reason)"
        case .badResponse(let code): return "Clash API ответил кодом \(code)"
        }
    }
}

/// sing-box's Clash API, read only: what runs and how much it carries.
@DependencyClient
struct ClashAPI: Sendable {
    var runtime: @Sendable (_ endpoint: ClashEndpoint) async throws -> SingBoxRuntime
}

extension ClashAPI: DependencyKey {
    static let liveValue: ClashAPI = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.waitsForConnectivity = false
        let session = Session(configuration: configuration)

        @Sendable func get<T: Decodable & Sendable>(_ type: T.Type, _ endpoint: ClashEndpoint, _ path: String) async throws -> T {
            var headers: HTTPHeaders = [:]
            if !endpoint.secret.isEmpty {
                headers.add(.authorization(bearerToken: endpoint.secret))
            }
            let task = session.request(endpoint.baseURL.appending(path: path), headers: headers)
                .validate()
                .serializingDecodable(T.self)
            return try unwrap(await task.response)
        }

        return ClashAPI(runtime: { endpoint in
            async let version = get(ClashVersionDTO.self, endpoint, "version")
            async let configs = get(ClashConfigsDTO.self, endpoint, "configs")
            async let proxies = get(ClashProxiesDTO.self, endpoint, "proxies")
            async let connections = get(ClashConnectionsDTO.self, endpoint, "connections")
            let (v, c, p, n) = try await (version, configs, proxies, connections)
            // sing-box adds a connection's bytes to the totals only once it
            // closes, so the open ones count too, or speed reads zero.
            let open = n.connections ?? []
            return SingBoxRuntime(
                version: v.version,
                mode: c.mode,
                modes: c.modeList ?? ["rule", "global", "direct"],
                groups: outboundGroups(from: p.proxies),
                connections: open.count,
                downloadTotal: n.downloadTotal + open.reduce(0) { $0 + ($1.download ?? 0) },
                uploadTotal: n.uploadTotal + open.reduce(0) { $0 + ($1.upload ?? 0) },
                memoryBytes: n.memory
            )
        })
    }()

    static let testValue = ClashAPI()
}

private func unwrap<T>(_ response: DataResponse<T, AFError>) throws -> T {
    switch response.result {
    case .success(let value):
        return value
    case .failure(let error):
        if let code = response.response?.statusCode {
            if code == 401 || code == 403 { throw ClashAPIError.unauthorized }
            throw ClashAPIError.badResponse(code)
        }
        throw ClashAPIError.unreachable(error.underlyingError?.localizedDescription ?? error.localizedDescription)
    }
}

extension DependencyValues {
    var clashAPI: ClashAPI {
        get { self[ClashAPI.self] }
        set { self[ClashAPI.self] = newValue }
    }
}
