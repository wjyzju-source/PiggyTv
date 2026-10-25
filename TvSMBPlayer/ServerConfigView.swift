import SwiftUI

struct ServerConfigView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var port = "445"
    @State private var username = ""
    @State private var password = ""
    @State private var testing = false
    @State private var testMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    TextField("主机名或 IP（如 192.168.1.100）", text: $host)
                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)
                }
                Section("账户") {
                    TextField("用户名（默认 guest）", text: $username)
                    SecureField("密码", text: $password)
                }
                Section {
                    Button(testing ? "正在测试…" : "测试连接并列出共享") {
                        Task { await test() }
                    }
                    .disabled(testing)

                    Button("保存") {
                        save()
                    }
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let testMessage {
                    Section {
                        Text(testMessage)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .navigationTitle("服务器设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                host = model.config.host
                port = String(model.config.port)
                username = model.config.username
                password = model.config.password
            }
        }
    }

    private func currentConfig() -> ServerConfig {
        ServerConfig(
            host: host.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 445,
            username: username.isEmpty ? "guest" : username,
            password: password,
            share: ""
        )
    }

    private func test() async {
        testing = true
        testMessage = nil
        defer { testing = false }
        let manager = SMBManager(config: currentConfig())
        do {
            let shares = try await manager.listShares()
            let names = shares.prefix(8).map(\.name).joined(separator: "、")
            testMessage = "连接成功，发现 \(shares.count) 个共享：\(names)\(shares.count > 8 ? "…" : "")"
        } catch {
            testMessage = "连接失败：\(error.localizedDescription)"
        }
    }

    private func save() {
        model.save(currentConfig())
        dismiss()
    }
}
