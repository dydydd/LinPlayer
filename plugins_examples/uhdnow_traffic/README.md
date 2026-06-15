# UHDNow 流量统计插件

当 Emby 服务器（地址或名称）包含关键字 **`uhdnow`** 时，在首页媒体计数（电影 /
剧集 / 总共）旁边显示账户的 **剩余流量 / 总流量**。

## 工作原理
1. `onEnable` 注册首页统计扩展点 `homeStats`；是否显示由 handler **每次渲染时**
   根据当前服务器是否含 `uhdnow` 动态判断（切换服务器即时生效）。
2. 用「添加服务器时填写的账号密码」自动登录（无需手动填 Cookie）：
   - `POST https://www.uhdnow.com/api/v1/auth/login` 体 `{username, password}`
     → `{ ok, data: { token, expires_at } }`
   - `GET https://www.uhdnow.com/api/v1/traffic/me` 头 `Authorization: <token>`
     → `{ ok, data: { used_bytes, limit_bytes } }`
3. `剩余 = (limit_bytes - used_bytes) / 1024³`，`总 = limit_bytes / 1024³`，
   显示为 GB。token 缓存在 `ctx.storage`，过期（401）自动重登重试。

## 申请权限
`emby.read`（读服务器/用户名）、`emby.credentials`（读账密自动登录）、
`http`、`storage`、`ui`、`extensions`。HTTPS 白名单：`www.uhdnow.com`、`uhdnow.com`。

## 使用
1. 安装本插件，启用并同意权限。
2. 确保当前 Emby 服务器是用**账号密码**添加的（密码会随服务器保存；旧版本添加的
   服务器没存密码，需删除后重新添加一次）。
3. 回首页，即可在「剧集 / 总共」旁看到「剩余流量 / 总流量」。
4. 插件「设置」里有「刷新」按钮，可清缓存强制重新登录刷新。

> 非 uhdnow 服务器：插件不显示任何东西（按设计跳过）。

## 打包为 .lpk
```bash
dart run tools/pack_plugin.dart plugins_examples/uhdnow_traffic
# 产物：dist/plugins/com.linplayer.uhdnow-traffic-1.0.0.lpk
```
