# SenseDraft

[English](README.md) | **简体中文**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white) ![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white) [![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<p align="center">
  <img src="Resources/AppIcon.png" alt="SenseDraft 啄木鸟图标" width="128" height="128">
</p>

<p align="center"><strong>先确认原意，再写出自然英文。</strong></p>

SenseDraft 是一款开源 macOS 菜单栏应用，适合习惯用中文思考、需要用英文沟通的人。在正在使用的输入框按下快捷键，它会润色英文或把中文写成自然英文，并显示中文释义，帮助你核对结果是否准确表达了本意。单纯打字不会触发请求；未经你确认，应用也不会替换原文。

> **项目状态：**仍在早期开发阶段，目前需要从源码构建；尚无已签名的下载版本，也不保证兼容所有编辑器。各应用的验证情况见[兼容性记录](docs/compatibility.md)，测试步骤见[手动测试清单](docs/manual-testing.md)。

## 为什么使用 SenseDraft？

整个流程围绕“先确认意思，再替换文字”：

1. **读取当前输入框的完整内容。**无需预先选中文本，只有按下“分析”快捷键才会开始分析。
2. **对照英文建议和中文释义。**如果原英文已经自然，SenseDraft 会保留它并说明原因；你也可以直接编辑建议的英文。
3. **纠正被误解的意思。**修改中文释义并点击 **Regenerate**，即可重新生成英文；此时原输入框不会改变。
4. **确认后再替换。**写入前，SenseDraft 会核对原应用、输入框及完整原文。无法确认目标或写入结果时，仍可复制英文建议。

## 主要功能

| 项目 | 当前行为 |
| --- | --- |
| 输入 | 读取焦点输入框的完整内容，润色英文或将中文写成英文 |
| 核对 | 可编辑英文建议、查看中文释义、修改意思后重新生成；无需改写时会说明原因 |
| 控制 | “分析”和“替换”使用独立且可配置的全局快捷键；打字时不会在后台自动分析 |
| 写作风格 | 可设置语气、句首大小写、附加要求和英语地区偏好 |
| AI 接入 | 支持 OpenAI、DeepSeek、Kimi API Key，或通过符合条件的账号使用 **Sign in with ChatGPT**；凭据保存在 macOS 钥匙串 |
| 编辑器适配 | 优先通过辅助功能读取；对不暴露文本的编辑器，在按快捷键后尝试键盘操作 |
| 替换 | 写入前核对原文、写入后验证结果；无法可靠替换时可复制建议 |

## 从源码构建

需要 **macOS 14 或更新版本、Xcode 26 和 Swift 6**。目前尚无预编译发行版。

```sh
git clone https://github.com/AweStudioX/SenseDraft.git
cd SenseDraft
./Scripts/build-app.sh
open build/SenseDraft.app
```

首次启动后，按 **Permissions** 页面指引授予辅助功能权限。在 **Settings → AI Services** 中启用并配置想使用的 AI 来源，再在每个平台的模型设置中打开 **Show in results**。SenseDraft 按页面顺序展示所选来源的结果。Kimi 可选国内或国际 API 地址，需与 Key 所属平台一致。ChatGPT plan 需要符合条件的账号，且受账号使用额度限制；详见[连接说明](docs/chatgpt-plan.md)。API 凭据保存在钥匙串中。

默认快捷键：**⌘⌥E** 分析，**⌘⌥Return** 替换。可在 **Settings → Shortcuts** 修改或恢复默认值。设置窗口支持 **Escape** 或 **⌘W** 关闭；正在录制快捷键时，Escape 会先取消录制。

## 在编辑器中使用

1. 将光标放在英文或中文输入框，按“分析”快捷键。无需选中文本。
2. 有多个结果时，可在审阅面板用 ↑/↓ 选择。对照英文建议和中文释义；若修改了中文意思，点击 **Regenerate** 重新生成。
3. 审阅面板获得焦点、且光标不在结果编辑框内时，按 **回车**即可替换所选结果，也可点击 **Replace**。在结果编辑框内，回车仍会换行。如果 SenseDraft 无法恢复原编辑器焦点，请回到原输入框使用替换快捷键。无法可靠替换时，点击 **Copy English**。

审阅面板通常显示在输入框旁边，拖动后会记住你选择的位置。按 **Escape** 可关闭面板，原文不会改变。如果分析后原文发生变化，SenseDraft 会拒绝覆盖。检测到混合文本格式时，应用会在可能丢失格式的替换前要求确认。

## 隐私与编辑器限制

- SenseDraft 只在你按“分析”后读取当前输入框，并将文本发送给本次使用的已配置 AI 来源。本地历史记录采用加密保存，默认关闭。
- 某些编辑器不通过 macOS 辅助功能暴露文字。此时应用可能短暂全选并复制完整内容，再尝试恢复剪贴板。光标可能移到末尾，剪贴板历史工具也可能记录这次临时复制。
- 密码及受保护输入框不会被处理。部分编辑器无法可靠读取或替换文字；遇到这种情况可复制英文建议。
- 跨应用的行为仍需要使用打包后的应用逐项验证。[兼容性记录](docs/compatibility.md)会区分已观察结果和待测试项目。

本地构建若使用临时签名，代码变化后 macOS 可能要求重新授予辅助功能权限。可按[本地稳定签名指引](docs/local-signing.md)一次性创建签名身份，后续构建自动使用，通常无需反复授权。如果系统显示已开启权限，但 SenseDraft 仍提示 **Access needed**，请退出应用，在 **系统设置 → 隐私与安全性 → 辅助功能** 中移除旧条目，重新加入当前的 `build/SenseDraft.app`，再启动应用。

## 开发与贡献

```sh
swift test
swift build
./Scripts/build-app.sh
```

`Sources/SenseDraftCore/` 存放分析契约和会话规则；`Sources/SenseDraftMac/` 存放菜单栏应用、面板、快捷键及辅助功能适配；逻辑测试位于 `Tests/SenseDraftCoreTests/`。修改输入读取、替换、权限或登录时，也请按[手动测试清单](docs/manual-testing.md)验证，并在[兼容性记录](docs/compatibility.md)中记录实际结果。

欢迎提交 issue 和 pull request。报告编辑器问题时，请说明应用和 macOS 版本；修改行为时，请附上自动化与手动验证结果。报告中不要包含输入框内容、剪贴板数据、API Key 或 OAuth token。

## 许可证

SenseDraft 使用 [MIT 许可证](LICENSE)。
