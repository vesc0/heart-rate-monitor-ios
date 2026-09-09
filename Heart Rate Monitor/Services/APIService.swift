//
//  APIService.swift
//  Heart Rate Monitor
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let authTokenExpired = Notification.Name("authTokenExpired")
}

// MARK: - Error types

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(Int, String)
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Invalid URL."
        case .invalidResponse:     return "Invalid server response."
        case .unauthorized:        return "Session expired. Please log in again."
        case .serverError(_, let msg): return msg
        case .networkError(let e): return e.localizedDescription
        case .decodingError:       return "Failed to process server response."
        }
    }
}

// MARK: - Response types

struct AuthTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let name: String?
    let email: String?
    let age: Int?
    let gender: String?
    let heightCm: Int?
    let weightKg: Int?
    let healthIssues: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType   = "token_type"
        case name, username, email, age, gender
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case healthIssues = "health_issues"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decode(String.self, forKey: .tokenType)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .username)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        heightCm = try container.decodeIfPresent(Int.self, forKey: .heightCm)
        weightKg = try container.decodeIfPresent(Int.self, forKey: .weightKg)
        healthIssues = try container.decodeIfPresent(String.self, forKey: .healthIssues)
    }
}

struct UserProfileResponse: Decodable {
    let name: String?
    let email: String
    let age: Int?
    let gender: String?
    let heightCm: Int?
    let weightKg: Int?
    let healthIssues: String?

    enum CodingKeys: String, CodingKey {
        case name, username, email, age, gender
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case healthIssues = "health_issues"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .username)
        email = try container.decode(String.self, forKey: .email)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        heightCm = try container.decodeIfPresent(Int.self, forKey: .heightCm)
        weightKg = try container.decodeIfPresent(Int.self, forKey: .weightKg)
        healthIssues = try container.decodeIfPresent(String.self, forKey: .healthIssues)
    }
}

struct HeartRateEntryResponse: Codable, Identifiable {
    let id: String
    let bpm: Int
    let recordedAt: Date
    let createdAt: Date
    let stressLevel: String?
    let stressExplanation: String?
    let activityState: MeasurementState?

    enum CodingKeys: String, CodingKey {
        case id, bpm
        case recordedAt = "recorded_at"
        case createdAt  = "created_at"
        case stressLevel = "stress_level"
        case stressExplanation = "stress_explanation"
        case activityState = "activity_state"
    }
}

// MARK: - Stress prediction types

struct StressPredictRequest: Encodable {
    // Time-domain HRV
    let sdnn: Double
    let medianRR: Double
    let cvRR: Double
    let rmssd: Double
    let pnn50: Double
    let pnn20: Double
    let meanHR: Double
    let stdHR: Double
    let minHR: Double
    let maxHR: Double
    let hrRange: Double
    // Frequency-domain HRV
    let lfPower: Double
    let hfPower: Double
    let lfHfRatio: Double
    let totalPower: Double
    let lfNorm: Double
    // Nonlinear HRV
    let sd1: Double
    let sd2: Double
    let sdRatio: Double

    enum CodingKeys: String, CodingKey {
        case sdnn
        case medianRR = "median_rr"
        case cvRR = "cv_rr"
        case rmssd, pnn50, pnn20
        case meanHR = "mean_hr"
        case stdHR = "std_hr"
        case minHR = "min_hr"
        case maxHR = "max_hr"
        case hrRange = "hr_range"
        case lfPower = "lf_power"
        case hfPower = "hf_power"
        case lfHfRatio = "lf_hf_ratio"
        case totalPower = "total_power"
        case lfNorm = "lf_norm"
        case sd1, sd2
        case sdRatio = "sd_ratio"
    }
}

struct StressPredictResponse: Codable {
    let stressLevelPct: Double
    let isStressed: Bool
    let explanation: String?

    enum CodingKeys: String, CodingKey {
        case stressLevelPct = "stress_level_pct"
        case isStressed = "is_stressed"
        case explanation
    }
}

private struct APIErrorDetail: Decodable {
    struct FieldError: Decodable { let field: String; let message: String }
    let detail: String
    let errors: [FieldError]?

    // The API reports 422s as a generic detail plus per-field messages.
    var displayMessage: String {
        guard let first = errors?.first else { return detail }
        return "\(first.field.components(separatedBy: " -> ").last ?? first.field): \(first.message)"
    }
}

// MARK: - Service

final class APIService {

    static let shared = APIService()

    private let baseURL: String

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private let tokenKey = "auth.accessToken"

    var token: String? {
        get { Keychain.string(forKey: tokenKey) }
        set { Keychain.set(newValue, forKey: tokenKey) }
    }

    var isAuthenticated: Bool { token != nil }

    // MARK: Init

    // API_BASE_URL comes from Config.xcconfig via the Info.plist; a build without it
    // would otherwise fail later with an opaque networking error.
    private static func configuredBaseURL() -> String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), let scheme = url.scheme,
              scheme == "https" || scheme == "http", url.host != nil else {
            fatalError("Invalid APIBaseURL \"\(raw)\" — set API_BASE_URL in Config.xcconfig")
        }
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }

    private init() {
        baseURL = Self.configuredBaseURL()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            // Try full ISO-8601 with fractional seconds first, then without
            let formatters: [ISO8601DateFormatter] = {
                let full = ISO8601DateFormatter()
                full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let basic = ISO8601DateFormatter()
                basic.formatOptions = [.withInternetDateTime]
                return [full, basic]
            }()
            for fmt in formatters {
                if let date = fmt.date(from: str) { return date }
            }
            // If the string lacks a timezone indicator (Z or +hh:mm/-hh:mm) after the time
            if let tIndex = str.firstIndex(of: "T") {
                let tailStart = str.index(after: tIndex)
                let tail = String(str[tailStart...])
                if !tail.contains("Z") && !tail.contains("+") && !tail.contains("-") {
                    let withZ = str + "Z"
                    for fmt in formatters {
                        if let date = fmt.date(from: withZ) { return date }
                    }
                }
            }

            // Fallback: accept ISO-like timestamps without timezone that include fractional seconds
            let fracFallbacks = ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS"]
            for pattern in fracFallbacks {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                df.dateFormat = pattern
                if let date = df.date(from: str) { return date }
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Cannot decode date: \(str)")
        }

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // Adopt a token stored by a build that predates Keychain storage.
        if let legacy = UserDefaults.standard.string(forKey: tokenKey) {
            Keychain.set(legacy, forKey: tokenKey)
            UserDefaults.standard.removeObject(forKey: tokenKey)
        }
    }

    // MARK: - Auth

    // Registration already returns a session token, so no follow-up login is needed.
    @discardableResult
    func register(email: String, password: String) async throws -> AuthTokenResponse {
        let body: [String: Any] = ["email": email, "password": password]
        let response: AuthTokenResponse = try await request(.post, path: "/register", body: body)
        token = response.accessToken
        return response
    }

    @discardableResult
    func login(email: String, password: String) async throws -> AuthTokenResponse {
        let body: [String: Any] = ["email": email, "password": password]
        let response: AuthTokenResponse = try await request(.post, path: "/login", body: body)
        token = response.accessToken
        return response
    }

    func logout() {
        token = nil
    }

    // MARK: - Profile

    func fetchProfile() async throws -> UserProfileResponse {
        try await request(.get, path: "/me", authenticated: true)
    }

    func updateProfile(
        name: String? = nil,
        email: String? = nil,
        age: Int? = nil,
        gender: String? = nil,
        heightCm: Int? = nil,
        weightKg: Int? = nil,
        healthIssues: String? = nil
    ) async throws -> UserProfileResponse {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let email { body["email"] = email }
        if let age { body["age"] = age }
        if let gender { body["gender"] = gender }
        if let heightCm { body["height_cm"] = heightCm }
        if let weightKg { body["weight_kg"] = weightKg }
        if let healthIssues { body["health_issues"] = healthIssues }
        return try await request(.put, path: "/me", body: body, authenticated: true)
    }

    // MARK: - Heart-rate CRUD

    // Upserts on the server, so this doubles as the update path.
    @discardableResult
    func createHeartRateEntry(_ entry: HeartRateEntry) async throws -> HeartRateEntryResponse {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var body: [String: Any] = [
            "id": entry.id.uuidString.lowercased(),
            "bpm": entry.bpm,
            "recorded_at": isoFormatter.string(from: entry.date),
        ]
        if let stressLevel = entry.stressLevel { body["stress_level"] = stressLevel }
        if let explanation = entry.stressExplanation { body["stress_explanation"] = explanation }
        if let state = entry.activityState { body["activity_state"] = state.rawValue }
        return try await request(.post, path: "/heart-rate", body: body, authenticated: true)
    }

    func fetchHeartRateEntries(
        limit: Int = 5000,
        offset: Int = 0
    ) async throws -> [HeartRateEntryResponse] {
        try await request(
            .get,
            path: "/heart-rate?limit=\(limit)&offset=\(offset)",
            authenticated: true
        )
    }

    func deleteHeartRateEntry(id: String) async throws {
        try await requestNoContent(.delete, path: "/heart-rate/\(id.lowercased())", authenticated: true)
    }

    func deleteHeartRateEntries(ids: [String]) async throws {
        let normalizedIDs = ids.map { $0.lowercased() }
        let body: [String: Any] = ["ids": normalizedIDs]
        // batch-delete returns {"deleted": N}, not 204
        let _: [String: Int] = try await request(
            .post, path: "/heart-rate/batch-delete", body: body, authenticated: true
        )
    }

    // MARK: - Stress prediction

    func predictStress(features: StressPredictRequest) async throws -> StressPredictResponse {
        let bodyData = try JSONEncoder().encode(features)
        let bodyDict = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] ?? [:]
        return try await request(.post, path: "/stress-analysis", body: bodyDict, authenticated: true)
    }

    // MARK: - Internals

    private enum HTTPMethod: String {
        case get = "GET", post = "POST", put = "PUT", delete = "DELETE"
    }

    private func request<T: Decodable>(
        _ method: HTTPMethod,
        path: String,
        body: [String: Any]? = nil,
        authenticated: Bool = false
    ) async throws -> T {
        let data = try await rawRequest(method, path: path, body: body, authenticated: authenticated)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func requestNoContent(
        _ method: HTTPMethod,
        path: String,
        body: [String: Any]? = nil,
        authenticated: Bool = false
    ) async throws {
        _ = try await rawRequest(method, path: path, body: body, authenticated: authenticated)
    }

    private func rawRequest(
        _ method: HTTPMethod,
        path: String,
        body: [String: Any]?,
        authenticated: Bool
    ) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated {
            guard let token else { throw APIError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            token = nil
            NotificationCenter.default.post(name: .authTokenExpired, object: nil)
            throw APIError.unauthorized
        default:
            let detail = (try? decoder.decode(APIErrorDetail.self, from: data))?.displayMessage
                ?? "Unknown error"
            throw APIError.serverError(http.statusCode, detail)
        }
    }
}
