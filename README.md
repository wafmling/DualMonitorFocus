# 双屏焦点（Dual Monitor Focus）

Windows 双屏窗口管理小工具（AutoHotkey v2）：选中窗上主屏；副屏只留微信 / AI 对话类；文件夹可关闭；文档类最小化。

## 功能

- **主屏**：`Alt+Tab` 换窗松开后，或 `Alt+`` / `Ctrl+Alt+``，把当前窗提到主屏
  - 普通窗 → 铺满主屏工作区
  - 微信 / QQ / 企微 → 居中浮窗（默认约宽 58%、高 78%，可在 ini 调）
- **副屏**：排布对话 / AI 类窗口，以及哔哩哔哩播放页（播放页只留副屏，禁止扩展到主屏；最小化会拉起；1 窗占上半屏；2 上下 / 3 上中下 / 4 四宫格）。选片 / 首页在 `Alt+Tab` 或 `Alt+`` 选中时可上主屏
- **清理**：文件夹可关闭；Word / PPT / PDF 等最小化；其它非白名单最小化
- **托盘设置**：总开关、分屏样式、是否关文件夹、白名单编辑（进程名 / 标题关键词）

## 要求

- Windows 10 / 11
- [AutoHotkey v2](https://www.autohotkey.com/)

## 安装

1. 安装 AutoHotkey v2
2. 下载本仓库，保留 `FocusMain.ahk`
3. 双击运行，或建开机启动快捷方式：
   - 目标：`AutoHotkey64.exe` + 脚本完整路径
4. 托盘图标右键 → **设置…** 可开关与调白名单

配置会写到同目录 `FocusMain.ini`（首次保存设置后生成）。

## 热键

| 按键 | 作用 |
|------|------|
| `Alt+Tab` 后松开 Alt | 前台窗变了则自动排布 |
| `Alt+`` 或 `Ctrl+Alt+`` | 强制当前窗上主屏并排布副屏（最稳） |
| 托盘 → 立即重排 | 手动触发 |
| 托盘 → 刷新显示器 | 插拔显示器后用 |

## 配置（FocusMain.ini）

- `Enabled`：总开关
- `SecondarySlots`：2 / 3 / 4
- `CloseFolders`：是否关闭文件夹
- `ChatMainRatioW` / `ChatMainRatioH`：聊天窗相对主屏工作区的宽高比例

## 许可

MIT — 见 [LICENSE](LICENSE)。
