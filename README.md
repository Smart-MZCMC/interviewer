# smart-mzcmc-interviewer

采访端 —— 现场记者用来一键切换自己的采访状态。

**Flutter Web** 应用，构建产物由后端的 WebSocket 服务托管在 `/interviewer/`。
反代部署下对外是 `http://<域名>/interviewer/`。

## 界面

极简设计，占屏 80% 的巨大按钮：

- 🟢 **就绪**（`ready`）
- 🟡 **准备中**（`preparing`）
- 🔵 **未就绪**（`not_ready`）
- 🔴 **离线**（`offline`，由后端判定）

顶部显示采访点名称，底部显示 WebSocket 连接状态。

## 配置：运行期可改，不用重新编译

Web 端启动时会读**同目录的 `config.json`** 覆盖内置默认值
（见 `lib/main.dart` 的 `loadRuntimeConfig`）。所以部署到现场之后，
换服务器地址只要改一个 JSON 文件，刷新浏览器即可，**不需要重新构建**。

`backend/public/interviewer/config.json`（也就是线上那份）：

```json
{
  "wsUrl": "ws://zhdb.647382.xyz/ws",
  "projectId": 1,
  "pointCode": "point_1",
  "pointName": "采访点 1"
}
```

| 字段 | 说明 |
| :--- | :--- |
| `wsUrl` | WebSocket 地址。页面走 HTTPS 时**必须写 `wss://`**，否则浏览器按混合内容拦掉且不报错 |
| `projectId` | 目标项目 id，决定这条设备归属哪个项目 |
| `pointCode` | 这台设备代表哪个采访点。同一项目下多台设备各配一个不同的值 |
| `pointName` | 界面上显示的名字 |

逐字段校验：类型不对或缺失就保留内置默认值，**配置文件写坏不会让采访端起不来**。
`projectId` 写成字符串 `"1"` 也接受（现场手改容易在数字上多打一对引号）。

`lib/config.dart` 里的 `defaultXxx` 是编译期兜底，默认已指向正式域名，
所以直接构建出来的产物也能连上。

::: danger 本应用不使用 HTTP API
`serverUrl` 曾在这里，但代码里从未引用过——采访端只通过 WebSocket 通信。
所以配置里没有它。
:::

## 开发与构建

需要 **Flutter ≥ 3.44.0**（`pubspec.lock` 的约束）。

```bash
flutter pub get
flutter run -d chrome          # 本地调试
flutter analyze
flutter test
```

### 构建 + 部署一条命令

```bat
build-web.bat
```

它会执行 `flutter pub get` → 构建 → `trim-web.mjs` 裁剪死重 → 同步到
`backend/public/interviewer/` 并再次裁剪。

## ⚠️ 两个不能省的构建参数

```bash
flutter build web --release --base-href /interviewer/ --no-web-resources-cdn
```

漏掉任何一个，**构建过程都不报错，但线上是坏的**：

| 参数 | 漏掉的后果 |
| :--- | :--- |
| `--base-href /interviewer/` | 默认 base 是 `/`，所有资源解析到域名根目录 → **全部 404，浏览器白屏** |
| `--no-web-resources-cdn` | CanvasKit 默认从 `gstatic.com` 拉，校园内网没有外网 → **卡在白屏** |

在 Git Bash 下调用时还需要 `MSYS_NO_PATHCONV=1`，否则 `/interviewer/` 会被改写成
`C:/Program Files/Git/interviewer/`。`build-web.bat` 已经处理好了。

## 首屏体积与离线能力

原始产物 **39.8MB**，但浏览器冷启动只下载其中约 7.6MB。其余 30MB 是服务器磁盘
和部署上传的负担。`trim-web.mjs` 会删掉它们：

| 删掉 | 大小 | 为什么确定不会被下载 |
| --- | --- | --- |
| `*.symbols` 源映射 | 8.2MB | 只在 DevTools 调试时按需拉取 |
| `canvaskit/` 顶层渲染器 | 7.0MB | 引擎在 Chrome/Edge 上选的是 `chromium` 变体，顶层这份实测未被请求 |
| `skwasm*` / `wimp` | 11.9MB | 仅当 loader 显式配置对应 renderer 才加载 |
| `experimental_webparagraph/` | 4.0MB | 实验特性，需在 index.html 显式引入 |

> 「哪些不会被下载」是用浏览器 resource timing **实测**出来的，不是推测。
> 注意引擎实际选的是 `canvaskit/chromium/canvaskit.wasm`（5.6MB），
> 而顶层那份 6.9MB 的 `canvaskit.wasm` 从头到尾没被用到——这点很容易猜错。

裁剪后 **8.9MB**，且必需文件齐全性有断言兜底。

### 中文与拉丁字体都自带，不连 CDN

Flutter Web 默认从 `fonts.gstatic.com` 拉 **Noto Sans SC** 和 **Roboto**。校园内网
没有外网，这两个请求会一直挂着直到超时——**这是「首屏要等十多秒」的主要原因**，
而且超时后汉字根本不显示（只剩图标和灰色块）。

`make-subset-font.mjs` 从 Noto Sans SC 切出一份只含界面实际用到的字符的子集
（约 254 个汉字 + 完整 ASCII，**237KB**），并在 `pubspec.yaml` 里注册两遍：

- `NotoSansSCSubset` —— 界面文字
- `Roboto` —— **顶替引擎的默认字体族**，让它不必去 CDN 找

Noto Sans SC 采用 SIL Open Font License 1.1，允许再分发与子集化。

结果：**外部请求 0 个**，界面文字全部正常显示。改动界面文案后重跑
`node make-subset-font.mjs` 重新生成子集即可。

### 实测数据（本机 loopback，仅供参考）

| | 裁剪前 | 裁剪后 |
| :--- | --- | --- |
| 产物体积 | 39.8MB | **8.9MB** |
| 实际下载 | 7.61MB | 7.84MB（含子集字体） |
| 外部请求 | 6 个（gstatic 字体） | **0 个** |

下载量基本没变，变的是**不再有会超时的外部请求**——现场网络越慢，
这个差别越大。真正的下载大头是 `canvaskit/chromium/canvaskit.wasm`（5.6MB）。

## 通信

状态变更通过 WebSocket 上报，服务端再广播给导播端与包装端并写入日志：

```json
{
  "type": "interview_status",
  "project_id": 1,
  "payload": {
    "point_code": "point_1",
    "point_name": "采访点 1",
    "status": "ready"
  }
}
```

应用会周期性发送心跳（`chat` 类型 + `payload.message = "heartbeat"`）保活，断线后自动重连。
心跳在后端入库前就会被丢弃，不会进日志。

## 测试

`test/widget_test.dart` 覆盖状态切换，以及 `applyRuntimeConfig` 的逐字段校验。
测试**注入假的 WebSocketService**，不依赖任何真实服务器——换服务器地址不会让它变红。
