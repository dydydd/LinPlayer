// UHDNow 流量统计插件
//
// 行为：当 Emby 服务器地址包含关键字 "uhdnow" 时，在首页媒体计数旁注册一个
// 「流量」统计（剩余流量 / 总流量）。数据来自 uhdnow 用户面板页（SSR 渲染的 HTML，
// 形如「已用 12.90 GB ... 共 700.00 GB」）。
//
// 申请权限：emby.read（读服务器地址）、http、storage、ui、extensions。
// 域名白名单：www.uhdnow.com、uhdnow.com（manifest.httpAllowedHosts）。

'use strict';

// 命中这些关键字的 Emby 服务器才启用流量统计。
var KEYWORDS = ['uhdnow'];
var DEFAULT_URL = 'https://www.uhdnow.com/user';

function matchesKeyword(url) {
  var u = (url || '').toLowerCase();
  for (var i = 0; i < KEYWORDS.length; i++) {
    if (u.indexOf(KEYWORDS[i]) >= 0) return true;
  }
  return false;
}

function parseGB(html, re) {
  var m = html.match(re);
  return m ? parseFloat(m[1]) : null;
}

// 首页流量统计 handler：返回 { metrics: [{label, value}, ...] }
async function fetchTraffic() {
  var cookie = await ctx.storage.get('cookie');
  var url = (await ctx.storage.get('dashboardUrl')) || DEFAULT_URL;

  if (!cookie) {
    return { metrics: [{ label: '流量', value: '未配置' }] };
  }

  var res;
  try {
    res = await ctx.http.get(url, {
      headers: {
        'Cookie': cookie,
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'text/html'
      }
    });
  } catch (e) {
    ctx.log.error('请求流量页失败: ' + e);
    return { metrics: [{ label: '流量', value: '请求失败' }] };
  }

  if (res.status === 401 || res.status === 403) {
    return { metrics: [{ label: '流量', value: 'Cookie 失效' }] };
  }
  if (res.status !== 200 || typeof res.body !== 'string') {
    return { metrics: [{ label: '流量', value: '错误 ' + res.status }] };
  }

  var html = res.body;
  // 页面 SSR 渲染：「已用 12.90 GB</span><span>共 700.00 GB」
  var used = parseGB(html, /已用\s*([\d.]+)\s*GB/);
  var total = parseGB(html, /共\s*([\d.]+)\s*GB/);

  if (used === null || total === null) {
    ctx.log.warn('未能解析流量（页面结构变化或未登录）');
    return { metrics: [{ label: '流量', value: '解析失败' }] };
  }

  var remaining = Math.max(0, total - used);
  return {
    metrics: [
      { label: '剩余流量', value: remaining.toFixed(2) + ' GB' },
      { label: '总流量', value: total.toFixed(0) + ' GB' }
    ]
  };
}

// 注册/重注册首页流量统计。重注册会生成新的 handler 句柄，
// 使首页缓存失效，从而在保存设置后立即刷新数据。
async function registerTraffic() {
  await ctx.extensions.unregister('homeStats', 'traffic');
  await ctx.extensions.register('homeStats', {
    id: 'traffic',
    title: '流量',
    handler: fetchTraffic
  });
}

// 设置页（由 manifest 的 settingsPages.handler = "openSettings" 触发）。
async function openSettings() {
  var cookie = (await ctx.storage.get('cookie')) || '';
  var dashboardUrl = (await ctx.storage.get('dashboardUrl')) || DEFAULT_URL;

  var values = await ctx.ui.showForm({
    title: 'UHDNow 流量设置',
    fields: [
      {
        key: 'cookie',
        label: '登录 Cookie',
        type: 'password',
        default: cookie,
        hint: '在浏览器登录 uhdnow 后，从开发者工具复制请求里的 Cookie'
      },
      {
        key: 'dashboardUrl',
        label: '面板地址',
        type: 'text',
        default: dashboardUrl,
        hint: '默认 https://www.uhdnow.com/user'
      }
    ],
    submitLabel: '保存',
    cancelLabel: '取消'
  });

  if (!values) return;
  await ctx.storage.set('cookie', (values.cookie || '').trim());
  await ctx.storage.set('dashboardUrl', (values.dashboardUrl || DEFAULT_URL).trim());
  ctx.ui.showToast('已保存，回到首页即可看到最新流量');

  var serverUrl = (await ctx.emby.getServerUrl()) || '';
  if (matchesKeyword(serverUrl)) {
    await registerTraffic();
  }
}

ctx.onEnable(async function () {
  var serverUrl = (await ctx.emby.getServerUrl()) || '';
  if (!matchesKeyword(serverUrl)) {
    ctx.log.info('当前服务器（' + serverUrl + '）不含 uhdnow，跳过流量统计');
    return;
  }
  ctx.log.info('检测到 uhdnow 服务器，注册首页流量统计');
  await registerTraffic();
});

ctx.onDisable(function () {
  ctx.log.info('UHDNow 流量统计已禁用');
});
