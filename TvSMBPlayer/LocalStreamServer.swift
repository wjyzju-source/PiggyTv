import Foundation
import Network
import AMSMB2

/// 流式错误。
enum StreamError: LocalizedError {
    case portUnavailable
    var errorDescription: String? { "无法分配本地端口。" }
}

/// 本地 HTTP 流媒体服务。
///
/// 思路：在 127.0.0.1 上起一个 HTTP 服务，把 SMB 里的一个视频文件暴露为
/// `http://127.0.0.1:<port>/stream`。AVPlayer 请求该地址时会带 `Range` 头
/// （支持拖进度），服务端按需从 SMB 文件句柄读取对应字节流返回（206 分片）。
/// 这样 AVPlayer 只拉取需要的部分，实现"边下边播/流式播放"。
///
/// 需要共享已通过 `SMB2Manager.connectShare` 连接成功（由调用方保证）。
final class LocalStreamServer: @unchecked Sendable {
    private let client: SMB2Manager
    private let remotePath: String
    private let fileSize: Int64
    private let queue = DispatchQueue(label: "tvsamb.httpserver")
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private(set) var baseURL: URL?

    init(client: SMB2Manager, remotePath: String, fileSize: Int64) {
        self.client = client
        self.remotePath = remotePath
        self.fileSize = fileSize
    }

    /// 启动服务，返回可交给 AVPlayer 的播放地址。
    func start() async throws -> URL {
        let params = NWParameters.tcp
        // 只绑定回环地址，避免暴露到局域网。
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)

        let listener = try NWListener(using: params, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let p = listener.port {
                        continuation.resume(returning: p.rawValue)
                    } else {
                        continuation.resume(throwing: StreamError.portUnavailable)
                    }
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: self.queue)
        }

        let url = URL(string: "http://127.0.0.1:\(port)/stream")!
        self.baseURL = url
        return url
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            self.connections.forEach { $0.cancel() }
            self.connections.removeAll()
        }
    }

    // MARK: - 连接处理

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self] state in
            if state == .ready {
                self?.readRequest(connection)
            }
        }
        connection.start(queue: queue)
    }

    /// 读入请求头（直到 \r\n\r\n），再交给处理器。
    private func readRequest(_ connection: NWConnection) {
        var buffer = Data()
        let separator = Data("\r\n\r\n".utf8)

        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data, !data.isEmpty {
                    buffer.append(data)
                    if let range = buffer.range(of: separator) {
                        let headData = buffer[buffer.startIndex..<range.lowerBound]
                        let header = String(decoding: headData, as: UTF8.self)
                        self.handle(header, connection: connection)
                        return
                    }
                }
                if isComplete || error != nil {
                    connection.cancel()
                    return
                }
                receive()
            }
        }
        receive()
    }

    // MARK: - 请求解析与响应

    private func handle(_ header: String, connection: NWConnection) {
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            connection.cancel()
            return
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }
        let method = String(parts[0])
        let path = String(parts[1])

        var rangeHeader: String?
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if key == "range" { rangeHeader = value }
            }
        }

        guard method == "GET" || method == "HEAD" else {
            sendSimple(connection, status: 405, reason: "Method Not Allowed", body: "Method Not Allowed")
            return
        }

        Task {
            await self.serve(method: method, path: path, rangeHeader: rangeHeader, connection: connection)
        }
    }

    private func serve(method: String, path: String, rangeHeader: String?, connection: NWConnection) async {
        let size = fileSize
        guard size > 0 else {
            sendSimple(connection, status: 500, reason: "Internal Server Error", body: "Empty file")
            return
        }

        let isRangeRequest = rangeHeader != nil
        var start: Int64 = 0
        var end: Int64 = size - 1

        if let rangeHeader, let parsed = parseRange(rangeHeader, size: size) {
            start = parsed.start
            end = parsed.end
        } else if rangeHeader != nil {
            sendSimple(connection, status: 416, reason: "Range Not Satisfiable", body: "Range Not Satisfiable")
            return
        }

        guard start <= end, start < size else {
            sendSimple(connection, status: 416, reason: "Range Not Satisfiable", body: "Range Not Satisfiable")
            return
        }

        let length = end - start + 1

        // 响应头
        var response = isRangeRequest
            ? "HTTP/1.1 206 Partial Content\r\n"
            : "HTTP/1.1 200 OK\r\n"
        response += "Content-Type: \(mimeType(for: path))\r\n"
        response += "Accept-Ranges: bytes\r\n"
        response += "Content-Length: \(length)\r\n"
        if isRangeRequest {
            response += "Content-Range: bytes \(start)-\(end)/\(size)\r\n"
        }
        response += "Connection: close\r\n\r\n"

        do {
            try await send(Data(response.utf8), on: connection)
            // HEAD 请求只返回头，不返回正文。
            if method == "HEAD" {
                connection.cancel()
                return
            }
            // 按需从 SMB 读取字节流并返回。
            let stream: AsyncThrowingStream<Data, any Error> =
                client.contents(atPath: remotePath, range: start..<(start + length))
            do {
                for try await chunk in stream {
                    guard !chunk.isEmpty else { continue }
                    try await send(chunk, on: connection)
                }
            } catch {
                connection.cancel()
                return
            }
            connection.cancel()
        } catch {
            connection.cancel()
        }
    }

    /// 发送数据并等待写入完成（提供背压）。
    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private func sendSimple(_ connection: NWConnection, status: Int, reason: String, body: String) {
        var response = "HTTP/1.1 \(status) \(reason)\r\n"
        response += "Content-Type: text/plain\r\n"
        response += "Content-Length: \(body.utf8.count)\r\n"
        response += "Connection: close\r\n\r\n"
        var data = Data(response.utf8)
        data.append(Data(body.utf8))
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - 工具

    /// 解析 `bytes=start-end`、`bytes=start-`、`bytes=-suffix`。
    private func parseRange(_ header: String, size: Int64) -> (start: Int64, end: Int64)? {
        guard header.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst("bytes=".count)
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let first = parts.first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        let second = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

        if !first.isEmpty {
            guard let start = Int64(first) else { return nil }
            var end = size - 1
            if !second.isEmpty, let e = Int64(second) {
                end = min(e, size - 1)
            }
            return (start, end)
        } else if !second.isEmpty {
            guard let suffix = Int64(second) else { return nil }
            let start = max(0, size - suffix)
            return (start, size - 1)
        }
        return nil
    }

    private func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mkv": return "video/x-matroska"
        case "ts", "m2ts", "mts": return "video/mp2t"
        case "avi": return "video/x-msvideo"
        case "webm": return "video/webm"
        default: return "application/octet-stream"
        }
    }
}
