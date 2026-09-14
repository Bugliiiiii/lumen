import AppKit
import CryptoKit
import Foundation

struct UpdateRelease: Equatable {
    let version: VersionNumber
    let tagName: String
    let downloadURL: URL
    let downloadSize: Int64
    let checksumURL: URL
    let releasePageURL: URL
}

struct VersionNumber: Comparable, Equatable {
    let components: [Int]

    init?(_ value: String) {
        let base = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(whereSeparator: { $0 == "-" || $0 == "+" })
            .first ?? ""
        let parsed = base.split(separator: ".").map(String.init).compactMap(Int.init)
        guard !parsed.isEmpty, parsed.count == base.split(separator: ".").count else { return nil }
        components = parsed
    }

    static func < (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

@MainActor
final class UpdateService: ObservableObject {
    @Published private(set) var availableRelease: UpdateRelease?
    @Published private(set) var statusText = ""
    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false

    private static let repository = "Bugliiiiii/lumen"
    private static let assetName = "Lumen-macOS-arm64.dmg"
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    private let session: URLSession

    init(session: URLSession = .shared, initialRelease: UpdateRelease? = nil) {
        self.session = session
        availableRelease = initialRelease
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.0"
    }

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        statusText = "正在检查 GitHub Releases…"
        Task {
            defer { isChecking = false }
            do {
                let release = try await fetchLatestRelease()
                availableRelease = release
                statusText = release == nil ? "当前已是最新版本" : "发现新版本 \(release!.tagName)"
            } catch {
                statusText = "检查更新失败：\(error.localizedDescription)"
            }
        }
    }

    func downloadAndOpen() {
        guard let release = availableRelease, !isDownloading else { return }
        isDownloading = true
        statusText = "正在下载 \(release.tagName)…"
        Task {
            defer { isDownloading = false }
            do {
                let destination = try await downloadVerifiedDMG(release)
                statusText = "已下载，正在打开安装镜像"
                guard NSWorkspace.shared.open(destination) else {
                    throw UpdateError.cannotOpenInstaller
                }
            } catch {
                statusText = "更新失败：\(error.localizedDescription)"
            }
        }
    }

    nonisolated static func isVersionNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidateVersion = VersionNumber(candidate), let currentVersion = VersionNumber(current) else { return false }
        return candidateVersion > currentVersion
    }

    private func fetchLatestRelease() async throws -> UpdateRelease? {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("Lumen/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.validateHTTP(response)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard Self.isVersionNewer(release.tagName, than: currentVersion) else { return nil }
        guard let installer = release.assets.first(where: { $0.name == Self.assetName }),
              let checksums = release.assets.first(where: { $0.name == "SHA256SUMS.txt" }) else {
            throw UpdateError.missingAssets
        }
        return UpdateRelease(
            version: VersionNumber(release.tagName)!,
            tagName: release.tagName,
            downloadURL: try Self.validateAssetURL(installer.browserDownloadURL),
            downloadSize: try Self.validateDownloadSize(installer.size),
            checksumURL: try Self.validateAssetURL(checksums.browserDownloadURL),
            releasePageURL: try Self.validateReleasePageURL(release.htmlURL)
        )
    }

    private func downloadVerifiedDMG(_ release: UpdateRelease) async throws -> URL {
        let (temporaryURL, downloadResponse) = try await session.download(from: release.downloadURL)
        try Self.validateHTTP(downloadResponse)
        let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value == release.downloadSize else {
            throw UpdateError.invalidDownload
        }

        let (checksumData, checksumResponse) = try await session.data(from: release.checksumURL)
        try Self.validateHTTP(checksumResponse)
        let checksumText = String(decoding: checksumData, as: UTF8.self)
        let expectedHash = try Self.checksum(for: Self.assetName, in: checksumText)
        let actualHash = try await Task.detached(priority: .utility) {
            try Self.sha256(of: temporaryURL)
        }.value
        guard expectedHash.caseInsensitiveCompare(actualHash) == .orderedSame else {
            throw UpdateError.checksumMismatch
        }

        let downloads = try FileManager.default.url(
            for: .downloadsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let destination = Self.uniqueDestination(
            in: downloads,
            preferredName: "Lumen-\(release.tagName)-macOS-arm64.dmg"
        )
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private static func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.invalidResponse
        }
    }

    private static func validateAssetURL(_ url: URL) throws -> URL {
        guard url.scheme == "https", url.host?.lowercased() == "github.com",
              url.path.hasPrefix("/\(repository)/releases/download/") else {
            throw UpdateError.invalidURL
        }
        return url
    }

    private static func validateReleasePageURL(_ url: URL) throws -> URL {
        guard url.scheme == "https", url.host?.lowercased() == "github.com",
              url.path.hasPrefix("/\(repository)/releases/tag/") else {
            throw UpdateError.invalidURL
        }
        return url
    }

    private static func validateDownloadSize(_ size: Int64) throws -> Int64 {
        guard size > 0, size <= 500_000_000 else { throw UpdateError.invalidDownload }
        return size
    }

    private static func checksum(for assetName: String, in content: String) throws -> String {
        for line in content.split(whereSeparator: \Character.isNewline) {
            let parts = line.split(whereSeparator: \Character.isWhitespace)
            guard parts.count >= 2 else { continue }
            let hash = String(parts[0])
            let name = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            if name == assetName, hash.count == 64, hash.allSatisfy(\.isHexDigit) { return hash }
        }
        throw UpdateError.missingChecksum
    }

    private nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func uniqueDestination(in directory: URL, preferredName: String) -> URL {
        let preferred = directory.appendingPathComponent(preferredName)
        if !FileManager.default.fileExists(atPath: preferred.path) { return preferred }
        let extensionName = preferred.pathExtension
        let baseName = preferred.deletingPathExtension().lastPathComponent
        for suffix in 2...100 {
            let candidate = directory.appendingPathComponent("\(baseName) (\(suffix)).\(extensionName)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent("\(baseName)-\(UUID().uuidString).\(extensionName)")
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let size: Int64

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }
}

private enum UpdateError: LocalizedError {
    case invalidResponse
    case missingAssets
    case invalidURL
    case invalidDownload
    case missingChecksum
    case checksumMismatch
    case cannotOpenInstaller

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "GitHub 返回了无效响应"
        case .missingAssets: "最新版本缺少 macOS 安装包或校验文件"
        case .invalidURL: "GitHub 返回了无效的下载地址"
        case .invalidDownload: "更新包大小异常"
        case .missingChecksum: "校验文件中没有 macOS 安装包记录"
        case .checksumMismatch: "更新包校验失败，已取消安装"
        case .cannotOpenInstaller: "无法打开安装镜像"
        }
    }
}
