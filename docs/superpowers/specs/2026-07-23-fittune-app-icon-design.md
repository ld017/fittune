# FitTune App Icon 替换设计

## 目标

将用户提供的 `/Users/lindui017/Desktop/ChatGPT Image 2026年7月22日 22_49_52.png` 设置为 FitTune iPhone App Icon，在不改变图案、文字、配色和整体圆角设计的前提下，让主屏幕图标显示饱满、清晰。

## 图像处理

- 从原图四周各裁去 24 像素，减少外围空白。
- 将裁切结果高质量缩放为 1024×1024 PNG。
- 输出保持 RGB、无 Alpha 通道。
- 不重新绘制或生成图案，不调整人物、渐变、文字或边框。
- 裁切后保留完整圆角边框、人物和 `fittune` 文字。

## Xcode 集成

- 新建 `FitTune/Resources/Assets.xcassets`。
- 在其中新建 `AppIcon.appiconset`，使用现代 iOS 通用 1024×1024 图标资源。
- 将 Asset Catalog 加入 FitTune iOS target 的 Resources build phase。
- 将 `ASSETCATALOG_COMPILER_APPICON_NAME` 设置为 `AppIcon`。
- 本次仅替换 iPhone App 图标；不改 Widget 图形、应用内品牌界面或 Apple Watch 图标。

## 验证与交付

- 检查生成图为 1024×1024 且无透明通道。
- 使用 `actool`/Xcode Release 构建确认 Asset Catalog 无警告或错误。
- 检查构建产物包含 App Icon。
- 使用相同 Bundle ID 覆盖安装到已连接 iPhone，不卸载旧 App、不清除数据。
- 启动 App，确认安装后的版本可正常运行。
