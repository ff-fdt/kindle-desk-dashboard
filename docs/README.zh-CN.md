# Kindle Desk

给 Kindle 做的桌面看板：大时钟、天气、Codex 问题与回复、Mac 资源状态和 Kindle 电量，通过蓝牙更新，不依赖同一 Wi-Fi。

- 竖屏 1236 × 1648，面向墨水屏设计。
- 右下角 `EN / 中文` 切换界面语言，重启服务后保留。对话正文保留原文。
- 点一条对话打开全文，底部翻页，可返回总览。
- 仅显示“进行中 / 已完成”两种回合状态。“已完成”指本轮回复结束，不代表整个项目成功。
- 顶部下滑打开 Kindle 原生控制栏，可调亮度和暖光。
- 显示电脑 CPU、内存、磁盘和 Kindle 电量，不显示电脑电池或 Wi-Fi。

![中文界面，虚构演示数据](images/panel-zh.png)

## 本机预览

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.lock
.venv/bin/python -m playwright install chromium
.venv/bin/python desk.py --port 8791
```

打开 **http://127.0.0.1:8791/panel/**。没有接 Kindle 时也能预览；设备电量会显示等待。复制 `config/example.json` 为 `config/local.json` 可修改天气位置、时区、刷新频率和默认语言。

## 设备范围

开发设备是 Paperwhite 5 Signature Edition，固件 5.18.3；Mac 为 Apple Silicon。其他机型和固件尚未验证。需要已越狱设备及 root 维护入口，本项目不提供越狱或刷机包。

看板使用正常 GTK/X11 窗口，保留原生 X、framework 和窗口管理器。此前接收端已实机验证原生下拉亮度及重复下滑。新增触摸回传、电量链路和冷启动自启仍需独立验证。安装默认关闭自启，先验证手动模式；Mac 程序更新后可能需要重新允许蓝牙权限。

详细安装、编译、配对与恢复见 [SETUP](SETUP.md)，数据协议见 [PROTOCOL](PROTOCOL.md)。真实运行状态、对话截图、书籍、备份、密钥及本机配置不应进入 Git。公开仓库不包含个人部署历史。

天气数据由 [Open-Meteo](https://open-meteo.com/) 提供（CC BY 4.0），署名放在文档中。图标及其他依赖来源见 [英文 README](../README.md#credits)。项目采用 MIT，第三方文件保留各自许可证。
