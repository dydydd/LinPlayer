package com.linplayer.tvlegacy;

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
import org.json.JSONException;

public final class ServersActivity extends AppCompatActivity {
    static final String EXTRA_REQUIRE_ONE = "require_one";

    private boolean requireOne;

    private RecyclerView listView;
    private ServerAdapter adapter;

    private ImageView qrImage;
    private TextView qrUrlText;

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
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
                                                "Active: " + server.effectiveName(),
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
        RemoteInfo info = RemoteControl.ensureStarted(this);
        String url = info != null ? info.firstRemoteUrl() : "";
        if (qrUrlText != null) {
            qrUrlText.setText(url.isEmpty() ? "No LAN IP" : url);
        }
        if (qrImage != null) {
            Bitmap bmp = url.isEmpty() ? null : QrCodeUtil.render(url, dpToPx(280));
            qrImage.setImageBitmap(bmp);
        }
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
        String[] items = new String[] {"Edit", "Sync Lines", "Relogin", "Delete"};
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
                .setTitle("Delete?")
                .setMessage(server.effectiveName())
                .setPositiveButton(
                        "Delete",
                        (d, w) -> {
                            try {
                                ServerStore.delete(getApplicationContext(), server.id);
                                Toast.makeText(this, "Deleted", Toast.LENGTH_SHORT).show();
                                refresh();
                            } catch (JSONException e) {
                                Toast.makeText(this, "Delete failed: " + e.getMessage(), Toast.LENGTH_LONG)
                                        .show();
                            }
                        })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void syncLines(ServerConfig server) {
        if (server == null) return;
        String token = server.apiKey != null ? server.apiKey.trim() : "";
        if (token.isEmpty()) {
            Toast.makeText(this, "Missing token. Relogin first.", Toast.LENGTH_LONG).show();
            return;
        }
        Toast.makeText(this, "Syncing...", Toast.LENGTH_SHORT).show();
        new Thread(
                        () -> {
                            try {
                                List<ServerLine> synced =
                                        EmbyApi.fetchExtDomains(
                                                getApplicationContext(), server.baseUrl, token, false);
                                List<ServerLine> merged = mergeLines(server.lines, synced);
                                ServerConfig updated =
                                        new ServerConfig(
                                                server.id,
                                                "emby",
                                                server.baseUrl,
                                                token,
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
                                            Toast.makeText(this, "Synced", Toast.LENGTH_SHORT).show();
                                            refresh();
                                        });
                            } catch (Exception e) {
                                runOnUiThread(
                                        () ->
                                                Toast.makeText(
                                                                this,
                                                                "Sync failed: " + String.valueOf(e.getMessage()),
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
            Toast.makeText(this, "Missing username", Toast.LENGTH_LONG).show();
            return;
        }
        Toast.makeText(this, "Logging in...", Toast.LENGTH_SHORT).show();
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
                                if (token.isEmpty()) throw new IllegalStateException("missing token");

                                String name = server.displayName;
                                if (name == null || name.trim().isEmpty()) {
                                    try {
                                        name = EmbyApi.fetchServerName(getApplicationContext(), baseUrl, token);
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
                                                    getApplicationContext(), baseUrl, token, true);
                                    merged = mergeLines(merged, synced);
                                } catch (Exception ignored) {
                                    // best-effort
                                }

                                ServerConfig updated =
                                        new ServerConfig(
                                                server.id,
                                                "emby",
                                                baseUrl,
                                                token,
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
                                            Toast.makeText(this, "Login OK", Toast.LENGTH_SHORT).show();
                                            refresh();
                                        });
                            } catch (Exception e) {
                                runOnUiThread(
                                        () ->
                                                Toast.makeText(
                                                                this,
                                                                "Login failed: " + String.valueOf(e.getMessage()),
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
