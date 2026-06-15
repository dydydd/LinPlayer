# UHDNow 流量统计插件

当 Emby 服务器地址包含关键字 **`uhdnow`** 时，在首页媒体计数（电影 / 剧集 / 总共）
旁边显示账户的 **剩余流量 / 总流量**。

## 工作原理
1. `onEnable` 时读取当前 Emby 服务器地址（`ctx.emby.getServerUrl`），
   命中关键字 `uhdnow` 才注册首页统计扩展点 `homeStats`，否则什么都不做。
2. 首页渲染时调用扩展 handler，向用户面板页（默认 `https://www.uhdnow.com/user`）
   发起 `ctx.http.get`，解析 SSR 渲染出的 `已用 X GB ... 共 Y GB`，
   计算 `剩余 = 总 - 已用`，返回两个指标交给宿主渲染。
3. 数据需要登录态：在插件「设置」里填入浏览器登录后的 **Cookie**。

## 申请权限
`emby.read`、`http`、`storage`、`ui`、`extensions`
（HTTPS 白名单：`www.uhdnow.com`、`uhdnow.com`）

## 使用
1. 安装本插件（见下方打包），启用并同意权限。
2. 在列表点「设置」，把浏览器登录 uhdnow 后的 Cookie 粘进去，保存。
   - 获取 Cookie：浏览器登录 `https://www.uhdnow.com/user` → F12 → Network →
     刷新 → 任意请求 → Request Headers → 复制 `Cookie:` 后面的整串。
3. 回到首页，即可在「剧集 / 总共」旁看到「剩余流量 / 总流量」。

> 当前服务器不含 `uhdnow` 时插件不显示任何东西（按设计跳过）。
> Cookie 失效会显示「Cookie 失效」，重新填入即可。

## 扩展点说明
本插件演示了新的 **`homeStats`** 扩展点：handler 返回
`{ metrics: [{ label, value }, ...] }`，宿主把它渲染在首页统计区。
（桌面端已接入；移动端/TV 端按相同方式读取 `pluginRegistryProvider` 即可接。）

## 打包为 .lpk
```bash
dart run tools/pack_plugin.dart plugins_examples/uhdnow_traffic
# 产物：dist/plugins/com.linplayer.uhdnow-traffic-1.0.0.lpk
```
