# Aether 发布与公证指南

> 文档状态：`Current`
> 适用范围：正式发布、签名、公证和分发，仅用于发布链路。
> 说明：日常功能开发与本地回归不要默认执行本文档中的步骤。

本文用于生成“普通用户可安装”的正式发布包（Developer ID 签名 + Notarization + Staple）。

## 1. 前置条件

- 本机钥匙串已安装 `Developer ID Application` 证书（Team: `4Z7654KAZZ`）。
- 已配置 notarytool 凭据（`NOTARY_PROFILE`）。
- 已安装 Xcode Command Line Tools。

## 2. 配置 NOTARY_PROFILE（仅首次）

```bash
xcrun notarytool store-credentials "AetherNotary" \
  --apple-id "你的AppleID邮箱" \
  --team-id "4Z7654KAZZ" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

验证凭据：

```bash
xcrun notarytool history --keychain-profile "AetherNotary"
```

## 3. 出正式发布包

```bash
cd /Volumes/SSD/Projects/Aether
NOTARY_PROFILE=AetherNotary ./Scripts/ReleaseForUsers.sh
```

脚本会执行：

- 无签名构建 App（避免开发证书阻塞）
- 用 `Developer ID Application` 重签 App 和 DEXT
- 生成 DMG 与 ZIP
- 对 DMG 做签名
- 提交 DMG 到 Apple Notary
- 对 App 和 DMG 执行 stapler

默认行为（无分发 profile）：

- 若未提供 `APP_PROVISION_PROFILE` 和 `DRIVER_PROVISION_PROFILE`，脚本会自动使用“兼容签名”模式。
- 兼容模式会移除 `Contents/Library/SystemExtensions`，并移除 `com.apple.developer.system-extension.install` entitlement。
- 这类包适合先分发主 App 与语音能力，不包含 DriverKit 系统扩展能力。

如需保留系统扩展能力，请显式提供 profile：

```bash
APP_PROVISION_PROFILE=/path/to/Aether.provisionprofile \
DRIVER_PROVISION_PROFILE=/path/to/AetherDriver.provisionprofile \
NOTARY_PROFILE=AetherNotary \
./Scripts/ReleaseForUsers.sh
```

产物路径：

- `.build/release/Aether.app`
- `.build/release/Aether_Installer.dmg`
- `.build/release/Aether.zip`

如果这次发布还要同步官网下载与 Sparkle appcast，发布前先确认：

- `App/` 当前版本号已是最终值。App 内更新链接里的 `version=` 取自 `CFBundleShortVersionString` / `MARKETING_VERSION`。
- `Website/src/data/downloads.ts` 里的 `CURRENT_DOWNLOAD_VERSIONS.stable` / `beta` 已同步成这次发布要上报给后台的短版本号。
- 后台 tracking gateway 已支持以下下载路径，而不只是 DMG：
  - `/download/Aether.dmg`
  - `/beta/Aether.dmg`
  - `/aether/*.zip`
  - `/aether-beta/*.zip`
  - `/aether/*.delta`
  - `/aether-beta/*.delta`

如果这次发布还要同步官网下载与 Sparkle appcast，再执行：

```bash
PUBLISH_SPARKLE=1 SPARKLE_CHANNEL=stable NOTARY_PROFILE=AetherNotary ./Scripts/ReleaseForUsers.sh
```

如需发布 Beta 通道，把 `SPARKLE_CHANNEL` 改为 `beta`。

这一步会把 DMG 复制到 `Website/public/download/` 或 `Website/public/beta/`。
同时会把 Sparkle 更新用的版本化 ZIP 复制到 `Website/public/aether/` 或 `Website/public/aether-beta/`，
并用 Sparkle 的 `generate_appcast` 生成 `appcast.xml` 和 delta 更新文件（`.delta`）。

发布脚本会自动做两类 URL 处理：

- 官网手动下载链接走 tracking gateway：
  - `https://auth.aether.7caifei.com/download/Aether.dmg?source=manual&channel=stable&version=<短版本号>`
  - `https://auth.aether.7caifei.com/beta/Aether.dmg?source=manual&channel=beta&version=<短版本号>`
- appcast 里的主 enclosure 与 delta enclosure 统一改成 tracking gateway，并带：
  - `source=update`
  - `channel=stable|beta`
  - `version=<该 item 的 shortVersionString>`

## 3.1 常用发布命令

### 3.1.1 从指定 Git 记录/分支发布（推荐）

`App/` 与 `Website/` 是两个独立 Git 仓库。发布包使用的是 `App/` 当前检出的代码与版本号。

发布前建议先确保 `App/` 工作区干净，并切到你要发布的 commit / 分支 / tag：

```bash
cd /Volumes/SSD/Projects/Aether/App
git fetch
git checkout <branch-or-sha-or-tag>
git status
```

正式包，不同步官网：

```bash
cd /Volumes/SSD/Projects/Aether/App
NOTARY_PROFILE=AetherNotary ./Scripts/ReleaseForUsers.sh
```

正式包，并同步 Stable 官网与 Sparkle：

```bash
cd /Volumes/SSD/Projects/Aether/App
PUBLISH_SPARKLE=1 SPARKLE_CHANNEL=stable NOTARY_PROFILE=AetherNotary ./Scripts/ReleaseForUsers.sh
```

Beta 包，并同步 Beta 官网与 Sparkle：

```bash
cd /Volumes/SSD/Projects/Aether/App
PUBLISH_SPARKLE=1 SPARKLE_CHANNEL=beta NOTARY_PROFILE=AetherNotary ./Scripts/ReleaseForUsers.sh
```

本地快速验证，跳过公证：

```bash
cd /Volumes/SSD/Projects/Aether/App
SKIP_NOTARIZE=1 ./Scripts/ReleaseForUsers.sh
```

### 3.1.2 部署官网（Website 仓库）

如果 `PUBLISH_SPARKLE=1`，脚本会修改 `Website/public/` 下的静态文件（DMG、版本化 ZIP、appcast、delta）。
提交 `Website/` 之前建议先做两项检查：

- 确认 `Website/public/aether/appcast.xml` 或 `Website/public/aether-beta/appcast.xml` 里的所有 `enclosure url=` 都已经是 `https://auth.aether.7caifei.com/...`，并带 `source=update`、`channel=`、`version=` 参数。
- 确认 `Website/src/data/downloads.ts` 中的 `CURRENT_DOWNLOAD_VERSIONS` 仍然和这次发布版本一致，否则官网手动下载会把错误版本号打到后台。

随后需要在 `Website/` 仓库提交并 push，触发站点部署：

```bash
cd /Volumes/SSD/Projects/Aether/Website
git status
git add public
git commit -m "Release: update Sparkle feeds"
git push
```

## 4. 本地快速验证（跳过公证）

```bash
cd /Volumes/SSD/Projects/Aether
SKIP_NOTARIZE=1 ./Scripts/ReleaseForUsers.sh
```

## 5. 开发快速构建（仅构建，不自动安装）

如果你正在进行功能开发，需要频繁验证构建结果，可以使用此脚本。它会执行生产打包，并把产物留在 `.build/release/`，不再自动覆盖 `/Applications/Aether.app`，也不会自动重启。

```bash
./Scripts/BuildAndInstall.sh
```

## 5. 验签命令（发布后）

```bash
APP="/Volumes/SSD/Projects/Aether/App/.build/release/Aether.app"
DMG="/Volumes/SSD/Projects/Aether/App/.build/release/Aether_Installer.dmg"

codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -t exec -vv "$APP"
xcrun stapler validate "$APP"

codesign --verify --verbose=4 "$DMG"
spctl -a -t open -vv --context context:primary-signature "$DMG"
spctl -a -t install -vv "$DMG"
xcrun stapler validate "$DMG"
```

关键检查（麦克风/语音识别权限）：

```bash
# 1) 必须包含以下 entitlement，否则系统可能不出现 Aether 麦克风授权项
codesign -d --entitlements :- "$APP" 2>/dev/null | \
  rg "com.apple.security.device.audio-input|com.apple.security.personal-information.speech-recognition"

# 2) 必须包含用途说明
/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :NSSpeechRecognitionUsageDescription" "$APP/Contents/Info.plist"
```

若缺少以上任一项，优先修复签名与 entitlements，再做权限排障。

说明：

- `spctl -t open` 在部分环境会出现 `Insufficient Context`，不等于包无效。
- 以 `--context context:primary-signature` 和 `-t install` 的结果为准。

## 6. 常见问题

- `ambiguous Developer ID Application`
  - 钥匙串有多张同名证书。发布脚本已使用 SHA-1 指纹签名以规避此问题。
- `The staple and validate action failed! Error 65`
  - 通常是“提交公证的对象”和“staple 的对象”不一致。当前脚本提交的是 DMG，并对 DMG 执行 staple。
- `No profile for team ...` / 开发签名报错
  - 走发布链路不依赖 Apple Development 证书，可直接使用 `ReleaseForUsers.sh`。
- App 内显示麦克风 `denied`，但系统麦克风列表没有 `Aether`
  - 先确认上面的 entitlement 与 usage description 检查都通过。
  - 然后执行：`tccutil reset Microphone com.7fei.Aether`，重启 App 再触发一次授权。

## 7. 发布事故记录

### 7.1 2026-04-01: Xcode 26.4 命令行发布链路卡死

现象：

- `ReleaseForUsers.sh` / `BuildRelease.sh` 的 fresh build 在命令行路径卡住。
- 卡点稳定出现在 `CreateBuildDescription -> ExecuteExternalTool clang -v -E -dM ...`。
- 这不是 Aether 业务源码编译报错，也不是签名、公证或上传链路失败；新的 `.app` 还没 fresh build 出来之前就挂住了。

定位结论：

- 同一条 `clang -v -E -dM ...` 命令，单独直接运行是正常的。
- 通过 `python3 subprocess.Popen(..., stdout=PIPE, stderr=PIPE)` 且不及时消费输出时，可以稳定复现挂起。
- 当前判断是 `Xcode 26.4 / SWBBuildService` 在命令行构建路径上的输出管道死锁/阻塞问题，不是项目业务逻辑本身的问题。

当前处理：

- 仓库内新增了 `Scripts/XcodeClangWrapper.sh`。
- `Scripts/BuildRelease.sh` 默认注入 `CC=Scripts/XcodeClangWrapper.sh`，作为命令行 release build 的 workaround。
- 截至 2026-04-01，`AETHER_UNIVERSAL=0` 的 `arm64` 发布链路已经用这套 workaround 完整验证过：fresh build、签名、公证、staple、Sparkle 发布、线上 appcast 校验均通过。

影响与后续：

- 当前可用的稳定发布路径是 `arm64` 单架构包。
- `universal` 不是产品方向废弃，而是发布基础设施仍需单独恢复与验证。
- 后续如继续排查，应优先把它当作 release/packaging 基础设施问题处理，而不是先怀疑业务代码。

### 7.2 2026-04-01: `Audit i18n` 被 Xcode 脚本沙箱拦截

现象：

- `PhaseScriptExecution Audit i18n` 失败。
- 直接报 `Sandbox ... deny file-read-data`，无法读取 `Scripts/AuditI18n.py`。

原因：

- Build Phase 开启了用户脚本沙箱，但 `Audit i18n` 没有声明必要的 `inputPaths`。

处理：

- 已在工程文件中补齐 `AuditI18n.py` 和资源目录输入路径。
- 当前该脚本不再是发布链路阻塞点。
