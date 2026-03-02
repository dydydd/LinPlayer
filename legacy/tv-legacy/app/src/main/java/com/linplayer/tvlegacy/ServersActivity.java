package com.linplayer.tvlegacy;

import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.linplayer.tvlegacy.remote.QrCodeUtil;
import com.linplayer.tvlegacy.remote.RemoteControl;
import com.linplayer.tvlegacy.remote.RemoteInfo;
import com.linplayer.tvlegacy.servers.EmbyApi;
import com.linplayer.tvlegacy.servers.ServerConfig;
import com.linplayer.tvlegacy.servers.ServerLine;
import com.linplayer.tvlegacy.servers.ServerStore;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.json.JSONException;

public final class ServersActivity extends AppCompatActivity {
    static final String EXTRA_REQUIRE_ONE = "require_one";

    private static final ExecutorService REMOTE_IO =
            Executors.newSingleThreadExecutor(
                    r -> {
                        Thread t = new Thread(r, "tv-legacy-remote-qr");
                        t.setDaemon(true);
                        return t;
                    });

    private boolean requireOne;

    private RecyclerView listView;
    private ServerAdapter adapter;

    private ImageView qrImage;
    private TextView qrUrlText;

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private volatile int remoteQrSeq = 0;
    @Nullable private volatile String remoteUrlCache;
    @Nullable private volatile Bitmap remoteQrCache;
    private final Runnable pollRunnable =
            new Runnable() {
                @Override
                public void run() {
                    refresh();
                    refreshRemoteQr();
                    if (requireOne && ServerStore.hasAny(ServersActivity.this)) {
                        goHome();
                        return;
                    }
                    mainHandler.postDelayed(this, 1000);
                }
            };

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_servers);

        requireOne = getIntent().getBooleanExtra(EXTRA_REQUIRE_ONE, false);

        Button backBtn = findViewById(R.id.btn_back);
        backBtn.setOnClickListener(v -> finish());

        Button addBtn = findViewById(R.id.btn_add_server);
        addBtn.setOnClickListener(v -> startActivity(new Intent(this, ServerEditActivity.class)));

        listView = findViewById(R.id.server_list);
        adapter =
                new ServerAdapter(
                        new ServerAdapter.Listener() {
                            @Override
                            public void onServerClicked(ServerConfig server) {
                                if (server == null || server.id == null || server.id.trim().isEmpty())
                                    return;
                                ServerStore.setActive(ServersActivity.this, server.id);
                                refresh();
                                Toast.makeText(
                                                ServersActivity.this,
                                                getString(R.string.toast_active, server.effectiveName()),
                                                Toast.LENGTH_SHORT)
                                        .show();
                            }

                            @Override
                            public void onServerLongClicked(ServerConfig server) {
                                if (server == null) return;
                                showManageDialog(server);
                            }
                        });
        listView.setAdapter(adapter);
        listView.setLayoutManager(new LinearLayoutManager(this));

        qrImage = findViewById(R.id.qr_image);
        qrUrlText = findViewById(R.id.qr_url);
        qrUrlText.setText(getString(R.string.qr_loading));
    }

    @Override
    protected void onResume() {
        super.onResume();
        refresh();
        refreshRemoteQr();
        if (requireOne && ServerStore.hasAny(this)) {
            goHome();
            return;
        }
        if (requireOne) {
            mainHandler.removeCallbacks(pollRunnable);
            mainHandler.postDelayed(pollRunnable, 1000);
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        mainHandler.removeCallbacks(pollRunnable);
    }

    private void refresh() {
        List<ServerConfig> servers = ServerStore.list(this);
        String activeId = ServerStore.getActiveId(this);
        adapter.setData(servers, activeId);
    }

    private void refreshRemoteQr() {
        final int seq = ++remoteQrSeq;
        final int sizePx = dpToPx(280);
        final Context appContext = getApplicationContext();

        REMOTE_IO.execute(
                () -> {
                    String url = "";
                    try {
                        RemoteInfo info = RemoteControl.ensureStarted(appContext);
                        url = info != null ? info.firstRemoteUrl() : "";
                        if (url == null) url = "";
                    } catch (Throwable ignored) {
                        url = "";
                    }

                    if (seq != remoteQrSeq) return;

                    final String u = url;

                    Bitmap bmp = null;
                    try {
                        String cachedUrl = remoteUrlCache;
                        Bitmap cachedBmp = remoteQrCache;
                        boolean sameUrl = cachedUrl != null && cachedUrl.equals(u);
                        if (!u.isEmpty() && (!sameUrl || cachedBmp == null)) {
                            bmp = QrCodeUtil.render(u, sizePx);
                        }
                    } catch (Throwable ignored) {
                        bmp = null;
                    }

                    final Bitmap rendered = bmp;
                    mainHandler.post(
                            () -> {
                                if (seq != remoteQrSeq) return;
                                if (isFinishing() || isDestroyed()) return;

                                if (qrUrlText != null) {
                                    qrUrlText.setText(
                                            u.isEmpty() ? getString(R.string.no_lan_ip) : u);
                                }

                                if (qrImage != null) {
                                    if (u.isEmpty()) {
                                        remoteUrlCache = null;
                                        remoteQrCache = null;
                                        qrImage.setImageBitmap(null);
                                        return;
                                    }

                                    if (rendered != null) {
                                        remoteUrlCache = u;
                                        remoteQrCache = rendered;
                                        qrImage.setImageBitmap(rendered);
                                        return;
                                    }

                                    Bitmap cached = remoteQrCache;
                                    qrImage.setImageBitmap(cached);
                                }
                            });
                });
    }

    private int dpToPx(int dp) {
        float density = getResources().getDisplayMetrics().density;
        return Math.round(dp * density);
    }

    private void goHome() {
        Intent i = new Intent(this, MainActivity.class);
        i.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(i);
        finish();
    }

    private void showManageDialog(ServerConfig server) {
        if (server == null || server.id == null || server.id.trim().isEmpty()) return;
        String[] items = getResources().getStringArray(R.array.server_manage_items);
        new AlertDialog.Builder(this)
                .setTitle(server.effectiveName())
                .setItems(
                        items,
                        (d, which) -> {
                            if (which == 0) {
                                Intent i = new Intent(ServersActivity.this, ServerEditActivity.class);
                                i.putExtra(ServerEditActivity.EXTRA_SERVER_ID, server.id);
                                startActivity(i);
                            } else if (which == 1) {
                                syncLines(server);
                            } else if (which == 2) {
                                relogin(server);
                            } else if (which == 3) {
                                confirmDelete(server);
                            }
                        })
                .show();
    }

    private void confirmDelete(ServerConfig server) {
        if (server == null) return;
        new AlertDialog.Builder(this)
                .setTitle(R.string.confirm_delete_title)
                .setMessage(server.effectiveName())
                .setPositiveButton(
                        R.string.delete,
                        (d, w) -> {
                            try {
                                ServerStore.delete(getApplicationContext(), server.id);
                                Toast.makeText(this, getString(R.string.toast_deleted), Toast.LENGTH_SHORT).show();
                                refresh();
                            } catch (JSONException e) {
                                Toast.makeText(
                                                this,
                                                getString(
                                                        R.string.toast_delete_failed,
                                                        String.valueOf(e.getMessage())),
                                                Toast.LENGTH_LONG)
                                        .show();
                            }
                        })
                .setNegativeButton(R.string.cancel, null)
                .show();
    }

    private void syncLines(ServerConfig server) {
        if (server == null) return;
        String token = server.apiKey != null ? server.apiKey.trim() : "";
        if (token.isEmpty()) {
            Toast.makeText(this, getString(R.string.toast_missing_token_relogin), Toast.LENGTH_LONG)
                    .show();
            return;
        }
        Toast.makeText(this, getString(R.string.toast_syncing), Toast.LENGTH_SHORT).show();
        new Thread(
                        () -> {
                            try {
                                List<ServerLine> synced =
                                        EmbyApi.fetchExtDomains(
                                                getApplicationContext(),
                                                server.baseUrl,
                                                token,
                                                server.apiPrefix,
                                                server.isType("jellyfin"),
                                                false);
                                List<ServerLine> merged = mergeLines(server.lines, synced);
                                ServerConfig updated =
                                        new ServerConfig(
                                                server.id,
                                                server.type,
                                                server.baseUrl,
                                                server.apiPrefix,
                                                token,
                                                server.userId,
                                                server.username,
                                                server.password,
                                                server.displayName,
                                                server.remark,
                                                server.iconUrl,
                                                merged);
                                boolean activate =
                                        server.id.equals(ServerStore.getActiveId(getApplicationContext()));
                                ServerStore.upsert(getApplicationContext(), updated, activate);
                                runOnUiThread(
                                        () -> {
                                            Toast.makeText(
                                                            this,
                                                            getString(R.string.toast_synced),
                                                            Toast.LENGTH_SHORT)
                                                    .show();
                                            refresh();
                                        });
                            } catch (Exception e) {
                                runOnUiThread(
                                        () ->
                                                Toast.makeText(
                                                                this,
                                                                getString(
                                                                        R.string.toast_sync_failed,
                                                                        String.valueOf(e.getMessage())),
                                                                Toast.LENGTH_LONG)
                                                        .show());
                            }
                        },
                        "tv-legacy-sync-lines")
                .start();
    }

    private void relogin(ServerConfig server) {
        if (server == null) return;
        String username = server.username != null ? server.username.trim() : "";
        if (username.isEmpty()) {
            Toast.makeText(this, getString(R.string.toast_missing_username), Toast.LENGTH_LONG).show();
            return;
        }
        Toast.makeText(this, getString(R.string.toast_logging_in), Toast.LENGTH_SHORT).show();
        new Thread(
                        () -> {
                            try {
                                EmbyApi.LoginResult login =
                                        EmbyApi.authenticateByName(
                                                getApplicationContext(),
                                                server.baseUrl,
                                                server.username,
                                                server.password);
                                String token = login != null ? login.accessToken : "";
                                String baseUrl = login != null ? login.baseUrl : server.baseUrl;
                                String apiPrefix = login != null ? login.apiPrefix : server.apiPrefix;
                                String userId = login != null ? login.userId : server.userId;
                                boolean jellyfin = login != null && login.jellyfin;
                                String serverType = jellyfin ? "jellyfin" : server.type;
                                if (token.isEmpty()) throw new IllegalStateException("missing token");

                                String name = server.displayName;
                                if (name == null || name.trim().isEmpty()) {
                                    try {
                                        name =
                                                EmbyApi.fetchServerName(
                                                        getApplicationContext(),
                                                        baseUrl,
                                                        token,
                                                        apiPrefix,
                                                        jellyfin);
                                    } catch (Exception ignored) {
                                        // best-effort
                                    }
                                }
                                if (name == null) name = "";

                                List<ServerLine> merged =
                                        mergeLines(
                                                server.lines,
                                                Collections.singletonList(new ServerLine("", baseUrl)));
                                try {
                                    List<ServerLine> synced =
                                            EmbyApi.fetchExtDomains(
                                                    getApplicationContext(),
                                                    baseUrl,
                                                    token,
                                                    apiPrefix,
                                                    jellyfin,
                                                    true);
                                    merged = mergeLines(merged, synced);
                                } catch (Exception ignored) {
                                    // best-effort
                                }

                                ServerConfig updated =
                                        new ServerConfig(
                                                server.id,
                                                serverType,
                                                baseUrl,
                                                apiPrefix,
                                                token,
                                                userId,
                                                server.username,
                                                server.password,
                                                name,
                                                server.remark,
                                                server.iconUrl,
                                                merged);
                                boolean activate =
                                        server.id.equals(ServerStore.getActiveId(getApplicationContext()));
                                ServerStore.upsert(getApplicationContext(), updated, activate);

                                runOnUiThread(
                                        () -> {
                                            Toast.makeText(
                                                            this,
                                                            getString(R.string.toast_login_ok),
                                                            Toast.LENGTH_SHORT)
                                                    .show();
                                            refresh();
                                        });
                            } catch (Exception e) {
                                runOnUiThread(
                                        () ->
                                                Toast.makeText(
                                                                this,
                                                                getString(
                                                                        R.string.toast_login_failed,
                                                                        String.valueOf(e.getMessage())),
                                                                Toast.LENGTH_LONG)
                                                        .show());
                            }
                        },
                        "tv-legacy-relogin")
                .start();
    }

    private static List<ServerLine> mergeLines(List<ServerLine> a, List<ServerLine> b) {
        LinkedHashMap<String, ServerLine> map = new LinkedHashMap<>();
        addLines(map, a);
        addLines(map, b);
        if (map.isEmpty()) return Collections.emptyList();
        return Collections.unmodifiableList(new ArrayList<>(map.values()));
    }

    private static void addLines(LinkedHashMap<String, ServerLine> map, List<ServerLine> lines) {
        if (map == null || lines == null || lines.isEmpty()) return;
        for (int i = 0; i < lines.size(); i++) {
            ServerLine l = lines.get(i);
            if (l == null) continue;
            String u = l.url != null ? l.url.trim() : "";
            if (u.isEmpty()) continue;

            ServerLine existing = map.get(u);
            if (existing == null) {
                map.put(u, l);
                continue;
            }

            String existingName = existing.name != null ? existing.name.trim() : "";
            String name = l.name != null ? l.name.trim() : "";
            if (existingName.isEmpty() && !name.isEmpty()) {
                map.put(u, new ServerLine(name, u));
            }
        }
    }
}
