# TvSMBPlayer —— Apple TV 上的 NAS·SMB 4K 视频播放器

一个 tvOS 应用：通过 SMB2/3 协议连接局域网 NAS，浏览共享目录，播放 4K 视频（解码由系统 AVPlayer 完成，支持 HEVC/H.265、H.264、HDR）。定位类似 Infuse 的轻量 MVP。

> ⚠️ 重要说明
> 本项目由 AI 在本机（Linux 云端）编写，**没有经过真实 Xcode 编译验证**。
> 代码与 AMSMB2 官方 API（v4.0.3）逐条核对过签名，理论上可编译，但请你按下方步骤在 Mac 上构建，若遇编译报错，把报错信息发我，我来修。

---

## 一、目录结构

```
ATVSMBPlayer/
├── project.yml                    # （可选）XcodeGen 一键生成工程用
├── TvSMBPlayer/
│   ├── TvSMBPlayerApp.swift       # App 入口
│   ├── ContentView.swift          # 首页 / 导航
│   ├── AppModel.swift             # 全局状态（配置持久化 + SMB 管理器）
│   ├── Models.swift               # 数据结构（ServerConfig / SMBEntry 等）
│   ├── SMBManager.swift           # AMSMB2 封装（连接/浏览/下载）
│   ├── ServerConfigView.swift     # 服务器设置 + 测试连接
│   ├── SharePickerView.swift      # 选择共享（卷）
│   ├── FileBrowserView.swift      # 目录浏览
│   ├── LocalStreamServer.swift    # 本地 HTTP 流媒体服务（支持 Range 分片）
│   ├── PlayerSession.swift        # 播放会话（连共享→起服务→AVPlayer）
│   ├── PlayerView.swift           # 播放页（流式播放 + 缓冲状态）
│   ├── Info.plist                 # 本地网络权限说明
│   └── TvSMBPlayer.entitlements   # App Sandbox 网络客户端权限
└── README.md
```

---

## 二、前置条件

1. **MacBook**，安装 **Xcode 16+**（App Store 免费）。
2. **Apple TV**（Apple TV HD/4K）与 Mac、NAS 在**同一局域网**。
3. **NAS 开启 SMB**（群晖/威联通/OpenWrt 均可）。建议：
   - 启用 **SMB2/3**（本应用使用 SMB2/3 协议，不依赖 SMB1）。
   - 记录主机 IP、用户名、密码、共享名。
4. 若要**在真机 Apple TV 上运行**，需要一个 **Apple 开发者账号**（免费 Apple ID 即可，Sign in with Apple ID，用它创建"个人团队"签名）。只在模拟器调试则无需账号。

---

## 三、在 Xcode 中建工程并跑起来（手动方式，约 5 分钟）

### 第 1 步：新建工程
Xcode → `File` → `New` → `Project...` → 选 **tvOS → App** → Next：
- Product Name：`TvSMBPlayer`
- Interface：**SwiftUI**；Language：**Swift**
- 取消勾选所有附加项 → 保存到 `ATVSMBPlayer` 目录同级即可。

### 第 2 步：替换默认源码
把本目录 `TvSMBPlayer/` 里的 Swift 文件**全部拖入**你的工程 target（勾选 "Copy items if needed" + 添加到 TvSMBPlayer target），覆盖/删掉 Xcode 自动生成的同名文件（如 `ContentView.swift`）。

### 第 3 步：添加 AMSMB2 依赖
Xcode → `File` → `Add Package Dependencies...`：
- 粘贴：`https://github.com/amosavian/AMSMB2`
- 版本规则选 `Up to Next Major from 4.0.3`
- 添加后，在 target 的 `General → Frameworks, Libraries, and Embedded Content` 里确认加入了 **AMSMB2**（默认已加）。

### 第 4 步：网络权限
1. target → `Info` 标签，右键空白处 `Add Row`，键名选/填：
   `NSLocalNetworkUsageDescription`，值填：`需要访问本地网络，以连接你的 NAS 服务器播放共享视频。`
2. target → `Signing & Capabilities` → 点 `+ Capability` 添加 **App Sandbox** → 勾选 **Network (client)**。
   （若你的工程已自动生成了 entitlements，把 `com.apple.security.network.client` 设为 true 也可以；本目录已提供 `TvSMBPlayer.entitlements` 可直接指定使用。）

### 第 5 步：签名（真机运行才需要）
target → `Signing & Capabilities` → `Team` 选择你的 Apple ID 团队。模拟器调试可跳过。

### 第 6 步：选择运行目标并编译
1. 顶部 Scheme 处选择你的 **Apple TV**（真机，需同一 Wi-Fi、设备已开"开发者模式"），或用 **Apple TV 模拟器**。
2. `⌘R` 编译运行。

### 可选：用 XcodeGen 一键生成工程
如果你装了 XcodeGen（`brew install xcodegen`），在 `ATVSMBPlayer` 目录执行 `xcodegen generate`，会自动生成 `TvSMBPlayer.xcodeproj`，然后打开即可，无需手动建工程。

---

## 四、使用流程

1. 首页 → **服务器设置**：填 NAS 的 IP、端口（默认 445）、用户名、密码 → 点"测试连接并列出共享"验证 → 保存。
2. 首页 → **浏览 NAS 文件** → 选择一个共享（如 `video`）。
3. 进入目录浏览，找到视频文件（mp4/mkv/mov 等）→ 点击播放。
4. 播放页会在应用内**起一个本地 HTTP 服务**，把 SMB 视频文件按需流式喂给系统播放器：**即点即播、可拖进度条、只拉取需要的字节**，4K 高码率也能流畅播放。

---

## 五、流式播放原理（类似 Infuse）

- **本地 HTTP 服务**：`LocalStreamServer.swift` 用 `Network.framework` 在 `127.0.0.1` 上起一个 HTTP 服务，把 SMB 里的视频文件暴露为 `http://127.0.0.1:<端口>/stream`。
- **Range 分片**：AVPlayer 播放时会带 `Range` 头请求字节范围（拖进度条也靠它）。服务端解析 Range，用 AMSMB2 的 `contents(atPath:range:)` 从 SMB 文件句柄**按需读取对应字节流**并返回 `206 Partial Content`。
- **解码**：解码交给 Apple TV 系统（AVPlayer），硬件原生支持 4K HEVC(H.265)、H.264、HDR10 / Dolby Vision（取决于你的 Apple TV 型号）。**只要封装容器能被 AVFoundation 识别，就能正常解 4K。**
- **兼容性提醒**：常见 4K 片源里 `MP4/M4V/MOV`（内封 H.264/HEVC）最稳；`MKV` 里的 H.264/HEVC 多数也能播，但**部分音轨（如 TrueHD 直通、部分 DTS）AVPlayer 可能不支持**——这是系统限制，不是代码问题。
- **安全**：服务只绑定回环地址（127.0.0.1），不会暴露到局域网其他设备。

---

## 六、上架注意事项

- **License**：AMSMB2 静态链接了 `libsmb2`（LGPL v2.1），整个工程因此受 LGPL v2.1 约束。若上架 App Store，**必须动态链接 AMSMB2**。该 SPM 包默认以动态 framework 提供（`library: dynamic`），Xcode 默认就是动态链接，通常无需额外处理；请勿手动把它改成静态链接进可执行文件。
- SMB 客户端属于本地网络功能，App Store 审核时按 Apple 的本地网络权限指引填写用途说明即可。

---

## 七、Codemagic 云端编译（无需本地 Mac 环境）

仓库已内置 **`codemagic.yaml`**，工程定义用 **`project.yml`（XcodeGen）**，云端会自动 `brew install xcodegen` → 生成工程 → `xcodebuild` 编译。

1. 把工程推到 Git（GitHub / GitLab / Bitbucket）。
2. Codemagic 控制台绑定仓库。
3. 选工作流运行：
   - **`tvos-build`**：编译 tvOS 模拟器 `.app`，**无需签名**，开箱即用，用于验证代码能否编译通过。
   - **`tvos-distribute`**：签名打包（真机 / TestFlight / App Store）。使用前需在 Codemagic 添加 **App Store Connect API Key** 集成，并改好 `BUNDLE_ID`、`APP_STORE_APP_ID`、`apple_id`（见 yaml 内注释）。

> 仓库根目录若是工程目录（含 `project.yml`），保持 `PROJECT_ROOT: "."`；若仓库根下还套了一层 `ATVSMBPlayer` 文件夹，则把 `PROJECT_ROOT` 改为 `ATVSMBPlayer`。

---

## 八、遇到问题排查

| 现象 | 处理 |
|------|------|
| 测试连接失败 | 确认 NAS IP/用户名/密码正确；确认 Apple TV 与 NAS 同网段；NAS 是否限制了 SMB 白名单；防火墙是否放行 445 |
| 连接成功但共享列表为空 | NAS 是否创建了共享文件夹；是否对当前账号开放权限 |
| 列表里看不到视频 | 确认扩展名是 mp4/mkv/mov/m4v/ts 等；NAS 文件名大小写、权限 |
| 能列出但播放黑屏/无声音 | 该封装格式或音轨 AVPlayer 不支持，换 MP4(H.264/HEVC) 片源测试 |
| 编译报错 | 把完整报错信息发给我，我来修 |

## 九、如何把报错发给我

在 Xcode 里 `⌘B` 编译，选中左侧错误列表，把红色错误信息完整复制，连同是"真机还是模拟器"一起发给我即可。
