import SwiftUI

struct FileBrowserView: View {
    @EnvironmentObject private var model: AppModel
    let share: String

    @State private var entries: [SMBEntry] = []
    @State private var pathStack: [String] = []   // 当前所在子目录栈（不含共享根）
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedVideo: SMBEntry?

    /// 当前目录路径，"" 表示共享根目录。
    private var currentPath: String {
        pathStack.joined(separator: "/")
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中…")
            } else if let errorMessage {
                VStack(spacing: 16) {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") { Task { await connectAndLoad() } }
                }
                .padding(40)
            } else {
                List {
                    if !pathStack.isEmpty {
                        Button {
                            pathStack.removeLast()
                        } label: {
                            Label("返回上级目录", systemImage: "arrow.up.circle")
                        }
                    }
                    ForEach(entries) { entry in
                        row(for: entry)
                    }
                }
            }
        }
        .navigationTitle(pathStack.isEmpty ? share : (pathStack.last ?? ""))
        .task { await connectAndLoad() }
        .onChange(of: pathStack) { _ in
            Task { await load() }
        }
        .fullScreenCover(item: $selectedVideo) { entry in
            PlayerView(share: share, entry: entry, manager: model.manager)
        }
    }

    @ViewBuilder
    private func row(for entry: SMBEntry) -> some View {
        if entry.isDirectory {
            Button {
                pathStack.append(entry.name)
            } label: {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.yellow)
                    Text(entry.name)
                    Spacer()
                }
            }
        } else if entry.isVideo {
            Button {
                selectedVideo = entry
            } label: {
                HStack {
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text(entry.name)
                        Text(entry.sizeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        } else {
            HStack {
                Image(systemName: "doc")
                    .foregroundStyle(.gray)
                Text(entry.name)
                Spacer()
            }
        }
    }

    private func connectAndLoad() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if model.manager.currentShare != share {
                try await model.manager.connectToShare(share)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load() async {
        do {
            entries = try await model.manager.listDirectory(atPath: currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
