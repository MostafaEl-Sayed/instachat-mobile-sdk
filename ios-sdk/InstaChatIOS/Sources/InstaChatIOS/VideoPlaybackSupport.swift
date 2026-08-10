import Foundation

struct VideoPlaybackSource: Equatable, Sendable {
  var url: URL
  var httpHeaders: [String: String]

  var isLocal: Bool {
    url.isFileURL
  }
}

enum MediaRetryPolicy {
  static let defaultRetryDelaysNanoseconds: [UInt64] = [
    500_000_000,
    1_000_000_000,
    2_000_000_000,
    4_000_000_000,
    8_000_000_000
  ]

  static func isTransient(_ error: Error) -> Bool {
    if let mediaError = error as? MediaDownloadError,
       case let .httpStatus(statusCode) = mediaError {
      return statusCode == 400 || statusCode == 404 || statusCode == 408 ||
        statusCode == 425 || statusCode == 429 || (500...599).contains(statusCode)
    }

    guard let urlError = error as? URLError else {
      return false
    }
    return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet]
      .contains(urlError.code)
  }
}

enum AuthenticatedMediaDataLoader {
  static func load(
    remoteURL: URL,
    authToken: String,
    session: URLSession = .shared,
    retryDelaysNanoseconds: [UInt64] = MediaRetryPolicy.defaultRetryDelaysNanoseconds
  ) async throws -> Data {
    if remoteURL.isFileURL {
      return try await Task.detached(priority: .utility) {
        try Data(contentsOf: remoteURL)
      }.value
    }

    var latestError: Error = MediaDownloadError.unavailable
    for attempt in 0...retryDelaysNanoseconds.count {
      do {
        var request = URLRequest(url: remoteURL)
        if !authToken.isEmpty {
          request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
          throw MediaDownloadError.unavailable
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
          throw MediaDownloadError.httpStatus(httpResponse.statusCode)
        }
        return data
      } catch {
        latestError = error
        guard retryDelaysNanoseconds.indices.contains(attempt), MediaRetryPolicy.isTransient(error) else {
          throw error
        }
        try await Task.sleep(nanoseconds: retryDelaysNanoseconds[attempt])
      }
    }

    throw latestError
  }
}

enum VideoPlaybackSourceResolver {
  static func resolve(
    remoteURL: URL,
    fileName: String,
    authToken: String,
    session: URLSession = .shared,
    retryDelaysNanoseconds: [UInt64] = MediaRetryPolicy.defaultRetryDelaysNanoseconds
  ) async throws -> VideoPlaybackSource {
    if let localURL = await AuthenticatedMediaCache.shared.existingLocalFileURL(
      for: remoteURL,
      fileName: fileName
    ) {
      return VideoPlaybackSource(url: localURL, httpHeaders: [:])
    }

    try await waitUntilRemoteVideoIsReady(
      remoteURL: remoteURL,
      authToken: authToken,
      session: session,
      retryDelaysNanoseconds: retryDelaysNanoseconds
    )

    return VideoPlaybackSource(
      url: remoteURL,
      httpHeaders: authorizationHeaders(authToken: authToken)
    )
  }

  private static func waitUntilRemoteVideoIsReady(
    remoteURL: URL,
    authToken: String,
    session: URLSession,
    retryDelaysNanoseconds: [UInt64]
  ) async throws {
    var latestError: Error = MediaDownloadError.unavailable

    for attempt in 0...retryDelaysNanoseconds.count {
      do {
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "HEAD"
        authorizationHeaders(authToken: authToken).forEach {
          request.setValue($0.value, forHTTPHeaderField: $0.key)
        }
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
          throw MediaDownloadError.unavailable
        }
        if (200..<300).contains(httpResponse.statusCode) || [405, 501].contains(httpResponse.statusCode) {
          return
        }
        throw MediaDownloadError.httpStatus(httpResponse.statusCode)
      } catch {
        latestError = error
        guard retryDelaysNanoseconds.indices.contains(attempt), MediaRetryPolicy.isTransient(error) else {
          throw error
        }
        try await Task.sleep(nanoseconds: retryDelaysNanoseconds[attempt])
      }
    }

    throw latestError
  }

  private static func authorizationHeaders(authToken: String) -> [String: String] {
    guard !authToken.isEmpty else {
      return [:]
    }
    return ["Authorization": "Bearer \(authToken)"]
  }
}
