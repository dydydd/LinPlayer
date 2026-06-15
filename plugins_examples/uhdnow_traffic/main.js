// UHDNow 流量统计插件
//
// 当 Emby 服务器（地址或名称）含关键字 "uhdnow" 时，在首页媒体计数旁显示
// 「剩余流量 / 总流量」。
//
// 登录：在插件「设置」里填写 **uhdnow 网站账号密码**（网站账号可能和 Emby 不同），
// 自动登录拿 token 后读取流量。也会回退到「添加服务器时的 Emby 账密」（若两者相同）。
//
// 接口（逆向自 www.uhdnow.com 前端，已实测）：
//   POST /api/v1/auth/login  {username,password} -> {ok, data:{token, expires_at}}
//   GET  /api/v1/traffic/me  (Header Authorization: <token>) ->
//        {ok, data:{used_bytes, limit_bytes}}

'use strict';

var KEYWORDS = ['uhdnow'];
var API_BASE = 'https://www.uhdnow.com';
var UA = 'Mozilla/5.0';
var GiB = 1073741824; // 1024^3

function matchesKeyword(text) {
  var u = (text || '').toLowerCase();
  for (var i = 0; i < KEYWORDS.length; i++) {
    if (u.indexOf(KEYWORDS[i]) >= 0) return true;
  }
  return false;
}

// 取登录凭据：优先用插件设置里填的网站账密，回退 Emby 账密。
async function getCreds() {
  var u = await ctx.storage.get('site_username');
  var p = await ctx.storage.get('site_password');
  if (u && p) return { username: u, password: p };
  try {
    var c = (await ctx.emby.getCredentials()) || {};
    if (c.username && c.password) return { username: c.username, password: c.password };
  } catch (e) { /* 没有 emby.credentials 权限或未存密码 */ }
  return null;
}

// 登录（带重试）。返回 { token } 或 { error, msg }。
//   error: NO_CREDS（没填账密）/ AUTH（账密错误，不重试）/ NETWORK（网络，已重试）
async function login() {
  var creds = await getCreds();
  if (!creds) return { error: 'NO_CREDS' };

  var attempts = 3;
  for (var i = 0; i < attempts; i++) {
    try {
      var res = await ctx.http.post(
        API_BASE + '/api/v1/auth/login',
        { username: creds.username, password: creds.password },
        { headers: { 'Content-Type': 'application/json', 'User-Agent': UA } }
      );
      var b = res.body;
      if (res.status === 200 && b && b.ok && b.data && b.data.token) {
        await ctx.storage.set('token', b.data.token);
        ctx.log.info('uhdnow 登录成功');
        return { token: b.data.token };
      }
      // 账号或密码错误：明确失败，不重试
      if (res.status === 400 || res.status === 401 ||
          (b && b.ok === false)) {
        var msg = (b && b.msg) ? b.msg : ('HTTP ' + res.status);
        ctx.log.error('登录被拒: ' + msg);
        return { error: 'AUTH', msg: msg };
      }
      ctx.log.warn('登录返回 ' + res.status + '，第 ' + (i + 1) + ' 次重试');
    } catch (e) {
      ctx.log.warn('登录网络异常，第 ' + (i + 1) + ' 次重试: ' + e);
    }
    if (i < attempts - 1) await ctx.sleep(400 * (i + 1)); // 400ms / 800ms 退避
  }
  return { error: 'NETWORK' };
}

async function requestTraffic(token) {
  return ctx.http.get(API_BASE + '/api/v1/traffic/me', {
    headers: { 'Authorization': token, 'User-Agent': UA }
  });
}

function gb(bytes) { return (Number(bytes) || 0) / GiB; }

// 拉流量（带重试 + 401 自动重登）。返回 { data } 或 { error, msg }。
async function getTraffic() {
  var token = await ctx.storage.get('token');
  if (!token) {
    var r0 = await login();
    if (!r0.token) return r0; // 透传错误
    token = r0.token;
  }

  for (var i = 0; i < 2; i++) {
    var res;
    try {
      res = await requestTraffic(token);
    } catch (e) {
      ctx.log.warn('流量请求异常，重试: ' + e);
      await ctx.sleep(400);
      continue;
    }
    var b = res.body;
    if (res.status === 200 && b && b.ok && b.data) {
      return { data: b.data };
    }
    // token 过期：清掉重登再试一轮
    if (res.status === 401 || (b && b.ok === false)) {
      await ctx.storage.delete('token');
      var r = await login();
      if (!r.token) return r;
      token = r.token;
      continue;
    }
    return { error: 'HTTP', msg: String(res.status) };
  }
  return { error: 'NETWORK' };
}

function errLabel(err) {
  switch (err) {
    case 'NO_CREDS': return '未配置';
    case 'AUTH': return '账密错误';
    case 'NETWORK': return '网络错误';
    default: return '获取失败';
  }
}

// 首页流量统计 handler：返回 { metrics: [{label, value}, ...] }
async function fetchTraffic() {
  var info = (await ctx.emby.getServerInfo()) || {};
  if (!(matchesKeyword(info.url) || matchesKeyword(info.baseUrl) ||
        matchesKeyword(info.name))) {
    return { metrics: [] }; // 非 uhdnow 服务器：不显示
  }

  var r = await getTraffic();
  if (!r.data) {
    return { metrics: [{ label: '流量', value: errLabel(r.error) }] };
  }

  var used = gb(r.data.used_bytes);
  var limit = gb(r.data.limit_bytes);
  var remaining = Math.max(0, limit - used);
  return {
    metrics: [
      { label: '剩余流量', value: remaining.toFixed(1) + ' GB' },
      { label: '总流量', value: limit.toFixed(0) + ' GB' }
    ]
  };
}

// 设置页：填写网站账号密码，保存即试登并给出反馈。
async function openSettings() {
  var info = (await ctx.emby.getServerInfo()) || {};
  var u = (await ctx.storage.get('site_username')) || (info.username || '');
  var p = (await ctx.storage.get('site_password')) || '';

  var values = await ctx.ui.showForm({
    title: 'UHDNow 流量 · 网站账号',
    fields: [
      {
        key: 'username',
        label: '网站用户名',
        type: 'text',
        default: u,
        hint: 'uhdnow 网站登录账号（可能与 Emby 不同）'
      },
      {
        key: 'password',
        label: '网站密码',
        type: 'password',
        default: p
      }
    ],
    submitLabel: '保存并登录',
    cancelLabel: '取消'
  });
  if (!values) return;

  await ctx.storage.set('site_username', (values.username || '').trim());
  await ctx.storage.set('site_password', (values.password || '').trim());
  await ctx.storage.delete('token'); // 用新账密强制重登

  var r = await login();
  if (r.token) {
    ctx.ui.showToast('登录成功，回到首页查看流量');
  } else if (r.error === 'AUTH') {
    ctx.ui.showToast('账号或密码错误：' + (r.msg || ''));
  } else if (r.error === 'NO_CREDS') {
    ctx.ui.showToast('请填写账号和密码');
  } else {
    ctx.ui.showToast('登录失败（网络问题），稍后会自动重试');
  }
  await registerTraffic();
}

// 无条件注册首页流量统计（是否显示由 handler 动态判断）。
async function registerTraffic() {
  await ctx.extensions.unregister('homeStats', 'traffic');
  await ctx.extensions.register('homeStats', {
    id: 'traffic',
    title: '流量',
    handler: fetchTraffic
  });
}

ctx.onEnable(async function () {
  ctx.log.info('UHDNow 流量统计已启用');
  await registerTraffic();
});

ctx.onDisable(function () {
  ctx.log.info('UHDNow 流量统计已禁用');
});
