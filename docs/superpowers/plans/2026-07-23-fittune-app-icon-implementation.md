# FitTune App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将用户提供的 FitTune 标志处理为合规的 1024×1024 iOS App Icon，并覆盖安装到现有 iPhone。

**Architecture:** 原图只进行固定对称裁切和高质量缩放，输出到独立 Asset Catalog；Xcode 主 target 显式引用该 catalog 并将 `AppIcon` 设为图标集。验证分为资源属性、Asset Catalog 编译、签名真机构建和覆盖安装四层。

**Tech Stack:** macOS `sips`、Xcode Asset Catalog、PBX project、`xcodebuild`、CoreDevice `devicectl`

## Global Constraints

- 输入文件固定为 `/Users/lindui017/Desktop/ChatGPT Image 2026年7月22日 22_49_52.png`。
- 原图四周各裁去 24 像素，裁切后保留完整圆角边框、人物和 `fittune` 文字。
- 输出必须为 1024×1024 RGB PNG 且无 Alpha 通道。
- 不改变人物、渐变、文字、配色和边框。
- 仅替换 FitTune iPhone App Icon，不修改 Widget、应用内品牌界面或 Apple Watch 图标。
- 覆盖安装必须使用 `com.codex.fittune`，不得卸载旧 App 或清除用户数据。

---

### Task 1: 生成并接入 App Icon Asset Catalog

**Files:**
- Create: `FitTune/Resources/Assets.xcassets/Contents.json`
- Create: `FitTune/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `FitTune/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- Modify: `FitTune.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: 1254×1254、无 Alpha 的用户源图。
- Produces: Xcode 可识别的 `AppIcon` 图标集与 FitTune target 资源引用。

- [ ] **Step 1: 运行资源前置检查并确认当前失败**

Run:

```bash
test -f FitTune/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

Expected: exit 1，因为仓库当前没有 App Icon Asset Catalog。

- [ ] **Step 2: 创建 Asset Catalog 元数据**

使用 `apply_patch` 创建：

```json
{
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

以及：

```json
{
  "images": [
    {
      "filename": "AppIcon-1024.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

- [ ] **Step 3: 裁切并缩放源图**

Run:

```bash
mkdir -p FitTune/Resources/Assets.xcassets/AppIcon.appiconset
sips --cropToHeightWidth 1206 1206 --cropOffset 24 24 \
  '/Users/lindui017/Desktop/ChatGPT Image 2026年7月22日 22_49_52.png' \
  --out /tmp/FitTune-AppIcon-cropped.png
sips --resampleHeightWidth 1024 1024 /tmp/FitTune-AppIcon-cropped.png \
  --out FitTune/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

Expected: 生成 1024×1024 PNG，人物、边框和 `fittune` 文字完整。

- [ ] **Step 4: 将 Asset Catalog 加入 iOS target**

使用 `apply_patch` 修改 `FitTune.xcodeproj/project.pbxproj`：

```text
B00000000000000000000048 /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = C00000000000000000000048 /* Assets.xcassets */; };
C00000000000000000000048 /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
```

将 file reference 加入 `D00000000000000000000008 /* Resources */`，将 build file 加入 `E00000000000000000000003 /* Resources */`，并在 FitTune Debug/Release build settings 中加入：

```text
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
```

- [ ] **Step 5: 验证图像和 catalog**

Run:

```bash
sips -g pixelWidth -g pixelHeight -g hasAlpha \
  FitTune/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
plutil -lint \
  FitTune/Resources/Assets.xcassets/Contents.json \
  FitTune/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
```

Expected: `pixelWidth: 1024`、`pixelHeight: 1024`、`hasAlpha: no`，两个 JSON 均为 `OK`。

- [ ] **Step 6: 提交资源集成**

```bash
git add FitTune/Resources/Assets.xcassets FitTune.xcodeproj/project.pbxproj
git commit -m "feat: add FitTune app icon"
```

### Task 2: 构建、检查并覆盖安装

**Files:**
- Verify: `FitTune/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- Verify: `FitTune.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 1 生成的 `AppIcon` catalog。
- Produces: 带新图标的签名 iPhone App，覆盖安装到 `com.codex.fittune`。

- [ ] **Step 1: 构建无签名 Release 模拟器产物**

Run:

```bash
xcodebuild -project FitTune.xcodeproj -scheme FitTune -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/FitTune-icon-sim CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`，无 `AppIcon` 或 Asset Catalog 警告。

- [ ] **Step 2: 检查产物图标声明**

Run:

```bash
plutil -p /tmp/FitTune-icon-sim/Build/Products/Release-iphonesimulator/FitTune.app/Info.plist \
  | rg 'CFBundleIcon|AppIcon'
```

Expected: 构建产物声明 `AppIcon`。

- [ ] **Step 3: 构建签名真机产物**

Run:

```bash
xcodebuild -project FitTune.xcodeproj -scheme FitTune -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/FitTune-icon-device -allowProvisioningUpdates build
```

Expected: `** BUILD SUCCEEDED **`，产物 Bundle ID 为 `com.codex.fittune`。

- [ ] **Step 4: 覆盖安装并启动**

Run:

```bash
xcrun devicectl device install app \
  --device DC7B8D70-E412-520C-BCE4-2089FAC48AC4 \
  /tmp/FitTune-icon-device/Build/Products/Debug-iphoneos/FitTune.app
xcrun devicectl device process launch \
  --device DC7B8D70-E412-520C-BCE4-2089FAC48AC4 \
  --terminate-existing com.codex.fittune
```

Expected: `App installed`，随后 `Launched application with com.codex.fittune bundle identifier`。

- [ ] **Step 5: 最终工作树检查**

Run:

```bash
git status --short
git log -2 --oneline
```

Expected: 工作树干净，最新提交为 `feat: add FitTune app icon`。

