import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        NavigationStack {
            HomeView()
                .environmentObject(model)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showConfig = false

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 8) {
                Text("SMB 视频播放器")
                    .font(.largeTitle.bold())
                Text(serverDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                SharePickerView()
                    .environmentObject(model)
            } label: {
                Label("浏览 NAS 文件", systemImage: "folder")
                    .font(.title3)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
            }

            Button {
                showConfig = true
            } label: {
                Label("服务器设置", systemImage: "gearshape")
                    .font(.title3)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
            }

            if model.config.host.isEmpty {
                Text("请先配置服务器地址")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showConfig) {
            ServerConfigView()
                .environmentObject(model)
        }
    }

    private var serverDescription: String {
        model.config.host.isEmpty
            ? "尚未配置服务器"
            : "\(model.config.host)\(model.config.username.isEmpty ? "" : " · \(model.config.username)")"
    }
}
