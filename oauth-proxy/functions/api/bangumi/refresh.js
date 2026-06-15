// POST /api/bangumi/refresh   body: { refresh_token, redirect_uri }
// 用 refresh_token 换新令牌。注入 app secret。
export async function onRequestPost({ env, request }) {
  const input = await request.json().catch(() => ({}));
  const refreshToken = input.refresh_token;
  const redirectUri = input.redirect_uri;
  if (!refreshToken || !redirectUri) {
    return new Response(
      JSON.stringify({ error: 'refresh_token and redirect_uri required' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }
  const form = new URLSearchParams({
    grant_type: 'refresh_token',
    client_id: env.BANGUMI_APP_ID,
    client_secret: env.BANGUMI_APP_SECRET,
    refresh_token: refreshToken,
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
