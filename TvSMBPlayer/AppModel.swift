import Foundation
import Combine

/// 全局应用状态：持有连接配置并管理 SMB 管理器。
final class AppModel: ObservableObject {
    @Published private(set) var config: ServerConfig
    @Published private(set) var manager: SMBManager

    private let configKey = "savedServerConfig"

    init() {
        // 先用局部变量取回配置，避免在存储属性初始化完成前读取 self.config。
        let initialConfig: ServerConfig
        if let data = UserDefaults.standard.data(forKey: "savedServerConfig"),
           let saved = try? JSONDecoder().decode(ServerConfig.self, from: data) {
            initialConfig = saved
        } else {
            initialConfig = ServerConfig()
        }
        self.config = initialConfig
        self.manager = SMBManager(config: initialConfig)
    }

    /// 保存新配置，并据此重建 SMB 连接管理器。
    func save(_ newConfig: ServerConfig) {
        config = newConfig
        manager = SMBManager(config: newConfig)
        if let data = try? JSONEncoder().encode(newConfig) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }
}
