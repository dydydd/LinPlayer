// POST /api/bangumi/token   body: { code, redirect_uri }
// 用授权码换令牌。注入 app secret，按 Bangumi 要求以表单编码请求。
export async function onRequestPost({ env, request }) {
  const input = await request.json().catch(() => ({}));
  const code = input.code;
  const redirectUri = input.redirect_uri;
  if (!code || !redirectUri) {
    return new Response(
      JSON.stringify({ error: 'code and redirect_uri required' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }
  const form = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: env.BANGUMI_APP_ID,
    client_secret: env.BANGUMI_APP_SECRET,
    code: code,
    redirect_uri: redirectUri,
  });
  const upstream = await fetch('https://bgm.tv/oauth/access_token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'Linplayer/1.0.0',
    },
    body: form.toString(),
  });
  const body = await upstream.text();
  return new Response(body, {
    status: upstream.status,
    headers: { 'Content-Type': 'application/json' },
  });
}
