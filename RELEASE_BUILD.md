# Release Build Guide

## 构建 Release 版本步骤

### 1. 打开项目
```bash
open BetterCapture.xcodeproj
```

### 2. 配置签名
- 点击左侧项目导航栏的 `BetterCapture`
- 选择 `Signing & Capabilities`
- 将 `Team` 设置为你的 Apple ID
- 将 `Bundle Identifier` 修改为唯一的 ID (如 `com.yourname.BetterCapture`)

### 3. 配置 Release 构建设置
- 选择项目 -> `Build Settings`
- 搜索 `Optimization Level`
- 确保 Release 配置为 `Fastest, Smallest [-Os]`

### 4. 归档构建
```
Product -> Archive
```
等待构建完成...

### 5. 导出应用
- 在 Organizer 窗口中选择刚创建的归档
- 点击 `Distribute App`
- 选择 `Copy App`
- 选择导出位置

### 6. 创建 DMG (可选)
```bash
# 使用 create-dmg 工具
brew install create-dmg

create-dmg \
  --volname "BetterCapture Installer" \
  --volicon "BetterCapture.icns" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --app-drop-link 600 185 \
  "BetterCapture-1.0.0.dmg" \
  "BetterCapture.app"
```

---

## 自动构建脚本

保存为 `build-release.sh`:

```bash
#!/bin/bash
set -e

# 配置
APP_NAME="BetterCapture"
SCHEME="BetterCapture"
VERSION="1.0.0"

# 清理
rm -rf build

# 构建
xcodebuild archive \
  -project ${APP_NAME}.xcodeproj \
  -scheme ${SCHEME} \
  -configuration Release \
  -archivePath build/${APP_NAME}.xcarchive \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# 导出
xcodebuild -exportArchive \
  -archivePath build/${APP_NAME}.xcarchive \
  -exportPath build/${APP_NAME}-${VERSION} \
  -exportOptionsPlist exportOptions.plist

echo "✅ Release build complete: build/${APP_NAME}-${VERSION}/${APP_NAME}.app"
```

---

## 发布检查清单

- [ ] 应用能正常启动
- [ ] 屏幕录制权限申请正常
- [ ] 开始/停止录制功能正常
- [ ] 音频录制正常
- [ ] 区域选择正常
- [ ] 设置能正常保存
- [ ] 自动更新(Sparkle)配置正确
- [ ] 版本号正确显示
- [ ] 图标显示正常

---

## GitHub Release 发布

1. 在 GitHub 创建新 Release
2. 版本号: `v1.0.0`
3. 标题: `BetterCapture 1.0.0`
4. 上传文件:
   - `BetterCapture.app.zip` (或 .dmg)
   - `BetterCapture-1.0.0.dmg` (可选)

---

## 已知限制

- 需要 macOS 15.2+
- 需要授予屏幕录制权限
- 首次启动可能需要右键点击 -> 打开 (未签名应用)
