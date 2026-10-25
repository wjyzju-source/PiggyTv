import SwiftUI

struct SharePickerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var shares: [ShareInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("正在连接 NAS…")
            } else if let errorMessage {
                VStack(spacing: 16) {
                    Text("连接失败").font(.title2)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") { Task { await load() } }
                }
                .padding(40)
            } else if shares.isEmpty {
                Text("没有发现共享目录")
                    .foregroundStyle(.secondary)
            } else {
                List(shares) { share in
                    NavigationLink {
                        FileBrowserView(share: share.name)
                            .environmentObject(model)
                    } label: {
                        HStack {
                            Image(systemName: "internaldrive")
                            VStack(alignment: .leading) {
                                Text(share.name)
                                if !share.comment.isEmpty {
                                    Text(share.comment)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("选择共享")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            shares = try await model.manager.listShares()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
