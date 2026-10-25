import Foundation

/// 服务器连接配置（NAS 的 SMB 地址与凭据），支持本地持久化。
struct ServerConfig: Codable, Equatable {
    var host: String = ""
    var port: Int = 445
    var username: String = "guest"
    var password: String = ""
    var share: String = ""

    /// 形如 `smb://192.168.1.100`（可选端口）
    var smbURL: URL? {
        var comps = URLComponents()
        comps.scheme = "smb"
        comps.host = host
        comps.port = port
        return comps.url
    }

    var credential: URLCredential {
        URLCredential(user: username, password: password, persistence: .forSession)
    }
}

/// NAS 上的一个共享（卷），例如 "video"、"public"。
struct ShareInfo: Identifiable, Hashable {
    let name: String
    let comment: String
    var id: String { name }
}

/// 目录 / 文件条目。
struct SMBEntry: Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modifiedDate: Date?

    var id: String { path }

    /// 是否是常见视频文件。
    var isVideo: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mp4", "mkv", "mov", "m4v", "ts", "avi", "webm", "3gp", "mts", "m2ts"].contains(ext)
    }

    /// 人类可读的文件大小。
    var sizeText: String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(size)
        var i = 0
        while value >= 1024 && i < units.count - 1 {
            value /= 1024
            i += 1
        }
        return String(format: "%.1f %@", value, units[i] as NSString)
    }

    /// 从 AMSMB2 返回的属性字典构造条目。
    static func from(_ dict: [URLResourceKey: Any]) -> SMBEntry {
        let name = dict[.nameKey] as? String ?? ""
        let path = dict[.pathKey] as? String ?? name
        let type = dict[.fileResourceTypeKey] as? URLFileResourceType
        let size: Int64 = {
            if let v = dict[.fileSizeKey] as? Int64 { return v }
            if let v = dict[.fileSizeKey] as? NSNumber { return v.int64Value }
            return 0
        }()
        let date = dict[.contentModificationDateKey] as? Date
        return SMBEntry(name: name, path: path, isDirectory: type == .directory, size: size, modifiedDate: date)
    }
}

/// 简单错误类型。
enum SMBError: LocalizedError {
    case invalidURL
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "服务器地址无效，请检查主机名或 IP。"
        case .notConnected: return "尚未连接到共享目录。"
        }
    }
}
