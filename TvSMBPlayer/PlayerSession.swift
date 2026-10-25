import Foundation
import Combine
import AVFoundation

/// 播放会话：启动本地流式服务，用系统 AVPlayer 播放 NAS 视频（边下边播）。
final class PlayerSession: ObservableObject {
    enum Phase: Equatable {
        case loading
        case buffering
        case playing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var player: AVPlayer?

    private let manager: SMBManager
    private let share: String
    private let entry: SMBEntry
    private var server: LocalStreamServer?
    private var playerItem: AVPlayerItem?
    private var cancellables: Set<AnyCancellable> = []

    init(manager: SMBManager, share: String, entry: SMBEntry) {
        self.manager = manager
        self.share = share
        self.entry = entry
    }

    /// 启动播放：连接共享 → 起本地 HTTP 服务 → AVPlayer 播放。
    @MainActor
    func start() async {
        phase = .loading
        do {
            if manager.currentShare != share {
                try await manager.connectToShare(share)
            }
            guard let raw = manager.rawClient else { throw SMBError.invalidURL }

            let server = LocalStreamServer(client: raw, remotePath: entry.path, fileSize: entry.size)
            self.server = server
            let url = try await server.start()
            play(url: url)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    @MainActor
    func stop() {
        player?.pause()
        player = nil
        playerItem?.cancelPendingSeeks()
        playerItem = nil
        cancellables.removeAll()
        server?.stop()
        server = nil
    }

    // MARK: - 私有

    @MainActor
    private func play(url: URL) {
        let item = AVPlayerItem(url: url)
        playerItem = item

        // 播放器状态监听（解码失败 / 就绪）。
        item.publisher(for: \.status)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .failed:
                    self.phase = .failed(item.error?.localizedDescription ?? "无法解码此视频")
                case .readyToPlay:
                    self.phase = .playing
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // 缓冲监听：显示"缓冲中"。
        item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .sink { [weak self] keepUp in
                guard let self else { return }
                if keepUp {
                    self.phase = .playing
                } else if self.phase == .playing || self.phase == .buffering {
                    self.phase = .buffering
                }
            }
            .store(in: &cancellables)

        let player = AVPlayer(playerItem: item)
        self.player = player
        player.play()
        phase = .buffering
    }
}
