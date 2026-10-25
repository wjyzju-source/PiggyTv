import Foundation
import Combine
import AMSMB2

/// 对 AMSMB2 的轻量封装：连接共享、浏览目录、下载文件。
final class SMBManager: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var currentShare: String?

    private let config: ServerConfig
    private let client: SMB2Manager?

    /// 底层 AMSMB2 客户端，供流式服务读取字节流使用。
    var rawClient: SMB2Manager? { client }

    init(config: ServerConfig) {
        self.config = config
        self.client = config.smbURL.flatMap { SMB2Manager(url: $0, credential: config.credential) }
    }

    /// 列出服务器上的所有共享（卷）。
    func listShares() async throws -> [ShareInfo] {
        guard let client else { throw SMBError.invalidURL }
        let shares = try await client.listShares()
        return shares.map { ShareInfo(name: $0.name, comment: $0.comment) }
    }

    /// 连接到指定共享。
    func connectToShare(_ share: String) async throws {
        guard let client else { throw SMBError.invalidURL }
        try await client.connectShare(name: share)
        self.currentShare = share
        self.isConnected = true
    }

    /// 列出当前共享下某个目录的内容。path 传 "" 表示共享根目录。
    func listDirectory(atPath path: String) async throws -> [SMBEntry] {
        guard let client else { throw SMBError.invalidURL }
        let dicts = try await client.contentsOfDirectory(atPath: path)
        return dicts
            .map { SMBEntry.from($0) }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    /// 把远端文件下载到本地 url，实时回调进度（0~1）。
    func downloadFile(atPath path: String, to url: URL, onProgress: @escaping (Double) -> Void) async throws {
        guard let client else { throw SMBError.invalidURL }
        var last: Double = -1
        try await client.downloadItem(atPath: path, to: url) { bytes, total in
            let fraction = total > 0 ? Double(bytes) / Double(total) : 0
            if fraction != last {
                last = fraction
                Task { @MainActor in onProgress(fraction) }
            }
            return true
        }
    }

    func disconnect() async {
        try? await client?.disconnectShare(gracefully: true)
        isConnected = false
        currentShare = nil
    }
}
