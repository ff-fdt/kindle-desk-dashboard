# 面板与维护 API

目标设备为 Paperwhite 5 Signature，**竖屏 1236 × 1648**，8-bit 灰度。后端和蓝牙接收端独立于页面样式，前端通过 panel/ 渲染 PNG，并通过认证触摸坐标回传支持阅读与翻页。

- 数据：`GET http://127.0.0.1:8791/api/state`。`generated_at` 是 Unix 秒；`timezone` 为 `Europe/London`。
- `weather` 含真实观测、最高/最低温、降雨概率、`available`、`stale`、`observed_at`、`fetched_at`。不可用/缓存必须如实展示。
- 当前 `codex.items` 按进行中优先、更新时间排序，含 `id`、`question`、`reply`、`at`、`updated_at`、`status`。`running/completed` 显示为“进行中/已完成”，指本轮回复状态，不代表整个项目成功。旧 completed/active 字段仅供兼容。
- 上传画面：`POST /api/frame`，原始 PNG body，附 `X-Kindle-Desk: frame` 和 `Content-Type: image/png`。必须是 1236×1648，文件 ≤262116 bytes。成功为 HTTP 204。
- 上传后接管 `state/device.png` 和预览；采集器继续刷新数据，但不覆盖上传的画面。前端应每分钟及数据变化时重新渲染、上传。删除忽略的 `state/frontend.png` 可恢复临时后端画面。
- 状态：`GET /api/transport`。`received_at` 表示 Kindle 校验、解密成功；`rendered_at` 表示接收端完成绘制后返回的确认（0.1.3 起为 GTK/X11 绘制并同步；旧版为 FBInk）。与 `advertising` 区分。

接口只绑定 Mac loopback，无 CORS 许可。可从本机渲染服务上传：

```sh
curl -X POST http://127.0.0.1:8791/api/frame \
  -H 'X-Kindle-Desk: frame' -H 'Content-Type: image/png' \
  --data-binary @portrait.png
```

不要提交任务内容、`state/`、配对密钥、SSH 密钥或实际设备备份。正式部署应从已记录的明确提交构建，并单独保存实机验证结果。


## 设备设置接口

`GET /api/device` 读取设备确认后的亮度、暖光、模式和 `observed_at`，不能将 HTTP 排队成功当作设备执行成功。

`POST /api/device`，JSON body，附 `X-Kindle-Desk: control`：

- `{"action":"brightness","value":12}`：亮度 0–24。
- `{"action":"warmth","value":8}`：暖光 0–24。
- `{"action":"native_settings"}`：临时恢复原生界面，在 Kindle 顶部下滑可打开设置；看板暂停覆盖屏幕。
- `{"action":"dashboard"}`：返回看板，并隐藏原生状态栏。
- `{"action":"status"}`：重新读取实际设置。

HTTP 202 为已排队，`seq` 为请求标识。通过 `GET /api/device` 检查相同 `seq`、`ok` 和实际值；尚有请求未确认时返回 409，120 秒未确认视为过期。蓝牙控制请求和执行回执都使用当前会话密钥认证。维护控制台为 `http://127.0.0.1:8791/settings`，无需前端先完成。

0.1.3 起，看板在真正 X 应用窗口中运行。屏幕最顶部 120px 内开始下滑至少 120px 会打开 Kindle 自带的快捷控制栏，收起仍回到同一看板。PNG 无需绘制亮度或色温控件；前端不需要实现这段设备手势。`native_settings` API 是离开看板回完整原生主页的维护入口，与这个下拉控制栏分开。

## 0.2 交互面板

内置 panel/ 是正式前端，不再依赖外部 PNG 上传。浏览器访问 /panel/，点击内容打开全文，底部翻页。POST /api/panel 携带 X-Kindle-Desk: panel 与 {"ui":{"page":0,"selected":null,"detailPage":0,"language":"zh"}} 保存阅读状态。Kindle 触摸经 BLE 认证回传后使用同一 DOM 命中检测；顶部下滑仍由原生窗口处理。kindle 字段提供实际电量、充电状态和读数时间，超过 180 秒标旧。
