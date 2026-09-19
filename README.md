# smart-mzcmc-interviewer

采访端 —— 现场记者用来一键切换自己的采访状态。

**Flutter Web** 应用，构建产物由后端 WebSocket 服务托管在 `http://<host>:3002/interviewer/`。

## 界面

极简设计，占屏 80% 的巨大按钮：

- 🟢 **就绪**（`ready`）
- 🟡 **准备中**（`preparing`）
- 🔵 **未就绪**（`not_ready`）
- 🔴 **离线**（`offline`，由后端判定）

顶部显示采访点名称，底部显示 WebSocket 连接状态。

## 配置

没有登录，**配置写死在** `lib/config.dart`：

```dart
static const String serverUrl = 'http://127.0.0.1:3000';
static const String wsUrl = 'ws://127.0.0.1:3002/ws';

// 该设备代表哪个采访点
static const int projectId = 1;
static const String pointCode = 'point_1';
static const String pointName = '采访点 1';
```

部署到现场设备前，改这里指向实际服务器，并给每台设备分配不同的 `pointCode`。

## 开发与构建

需要 **Flutter ≥ 3.44.0**（`pubspec.lock` 的约束）。

```bash
flutter pub get
flutter run -d chrome          # 本地调试
flutter analyze
flutter test

flutter build web --release    # 产物在 build/web
```

## 部署

把 `build/web` 的内容同步到后端的 `public/interviewer/`，后端会通过 `:3002/interviewer/` 提供服务，并按 SPA 规则回退到 `index.html`。

```bash
# 在 backend 目录下
cp -r ../interviewer/build/web/* public/interviewer/
```

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
