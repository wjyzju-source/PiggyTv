import SwiftUI
import AVKit

/// 播放页：连接共享 → 起本地 HTTP 流式服务 → AVPlayer 边下边播。
struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss

    let share: String
    let entry: SMBEntry
    @StateObject private var session: PlayerSession

    init(share: String, entry: SMBEntry, manager: SMBManager) {
        self.share = share
        self.entry = entry
        _session = StateObject(wrappedValue: PlayerSession(manager: manager, share: share, entry: entry))
    }

    var body: some View {
        ZStack {
            switch session.phase {
            case .loading:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("连接 NAS…")
                        .foregroundStyle(.secondary)
                }

            case .buffering:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("缓冲中…")
                        .foregroundStyle(.secondary)
                }

            case .playing:
                if let player = session.player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                }

            case .failed(let message):
                VStack(spacing: 16) {
                    Text("无法播放").font(.title2)
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("返回") { dismiss() }
                }
                .padding(40)
            }
        }
        .task { await session.start() }
        .onDisappear { session.stop() }
    }
}
