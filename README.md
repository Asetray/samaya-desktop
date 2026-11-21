# samaya-desktop

Samaya 的 Windows 原生桌面客户端，使用 C++20 和 Qt Quick。界面以 Samaya 的 Figma 画板和原仓库为依据。应用通过本机已有 Codex 安装提供的 `app-server proxy` 连接当前 Windows 用户的 App Server，沿用其登录状态和会话。

## 运行

1. 安装 Windows Codex 并登录。打开 Samaya 时，它会复用当前运行的本机 App Server，或在连接不可用时尝试在后台启动服务。
2. 使用安装版时，双击 `samaya-desktop-0.3.6-win-x64-setup.exe`，完成后从开始菜单打开 **Samaya Desktop → Samaya**。安装按当前用户进行，升级前请先退出旧版 Samaya。
3. 使用免安装版时，把 `samaya-desktop-0.3.6-win-x64-portable.zip` 完整解压到可写目录，然后运行里面的 `samaya-desktop.exe`。
4. 在「任务总览」打开原有会话，或点击「新任务」选择工作目录。输入消息后按 Enter 发送，Shift+Enter 换行。「待我处理」汇集当前连接收到的审批和问题。Ctrl+K 可搜索任务与项目。

两个发行包均包含 Qt、QML 模块、中文字体和 Visual C++ 运行库。目标系统为 Windows 10 1809 起及 Windows 11 x64。界面本身可离线打开，在线模型请求使用现有 Codex 账户。启动服务失败时，可打开 Windows Codex，再从「设置与连接」重新连接。Codex 使用自定义目录时，需让 Samaya 继承相同的 `CODEX_HOME`。白垣和苍渊主题在「设置与连接」中切换，偏好和置顶记录保存在本机当前用户下。

## 构建

构建机需有 MSVC x64 和 Windows SDK、CMake、Qt 6.8.3 MSVC x64（Qt Base、SVG、Declarative 和 Shader Tools）以及 NSIS 3.x。

```powershell
.\scripts\build-installer.ps1 -QtRoot 'C:\Qt\6.8.3\msvc2022_64' -MakeNsis 'C:\Program Files (x86)\NSIS\makensis.exe'
```

脚本在 `dist/` 生成安装器、免安装 ZIP 和 SHA-256 校验文件。便携 NSIS 工具链可使用 `-NsisRoot` 指定包含 Include、Plugins 和 Stubs 的目录。

设计参考见 [Figma](https://www.figma.com/design/TZOGfIsv1ESAQckxwg4lpa) 和 [Samaya 原仓库](https://github.com/MigoXV/samaya/tree/0aca23cb363dd94a83ae4e1c1b1f6c7deb94d97f)。发行组件见 [第三方声明](THIRD-PARTY.md)。
