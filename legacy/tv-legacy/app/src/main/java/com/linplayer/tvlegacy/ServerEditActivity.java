package com.linplayer.tvlegacy;

import android.content.Intent;
import android.os.Bundle;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import com.linplayer.tvlegacy.servers.EmbyApi;
import com.linplayer.tvlegacy.servers.ServerConfig;
import com.linplayer.tvlegacy.servers.ServerLine;
import com.linplayer.tvlegacy.servers.ServerStore;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import org.json.JSONException;

public final class ServerEditActivity extends AppCompatActivity {
    static final String EXTRA_SERVER_ID = "server_id";

    private String serverId;
    private ServerConfig existing;

    private EditText baseUrlInput;
    private EditText usernameInput;
    private EditText passwordInput;
    private EditText displayNameInput;
    private EditText remarkInput;
    private EditText iconUrlInput;
    private EditText lineNameInput;
    private EditText linesTextInput;
    private CheckBox activateCheckbox;
    private Button saveBtn;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_server_edit);

        serverId = getIntent().getStringExtra(EXTRA_SERVER_ID);
        if (serverId == null) serverId = "";
        existing = ServerStore.find(this, serverId);

        Button backBtn = findViewById(R.id.btn_back);
        backBtn.setOnClickListener(v -> finish());

        TextView title = findViewById(R.id.edit_title);
        title.setText(existing != null ? getString(R.string.edit_server) : getString(R.string.add_server));

        baseUrlInput = findViewById(R.id.base_url_input);
        usernameInput = findViewById(R.id.username_input);
        passwordInput = findViewById(R.id.password_input);
        displayNameInput = findViewById(R.id.display_name_input);
        remarkInput = findViewById(R.id.remark_input);
        iconUrlInput = findViewById(R.id.icon_url_input);
        lineNameInput = findViewById(R.id.line_name_input);
        linesTextInput = findViewById(R.id.lines_text_input);
        activateCheckbox = findViewById(R.id.activate_checkbox);
        saveBtn = findViewById(R.id.btn_save);
        Button deleteBtn = findViewById(R.id.btn_delete);

        String activeId = ServerStore.getActiveId(this);
        if (existing != null) {
            baseUrlInput.setText(existing.baseUrl);
            usernameInput.setText(existing.username);
            passwordInput.setText(existing.password);
            displayNameInput.setText(existing.displayName);
            remarkInput.setText(existing.remark);
            iconUrlInput.setText(existing.iconUrl);
            lineNameInput.setText(findActiveLineName(existing));
            linesTextInput.setText(buildOtherLinesText(existing));
            activateCheckbox.setChecked(existing.id != null && existing.id.equals(activeId));
        } else {
            activateCheckbox.setChecked(true);
            deleteBtn.setEnabled(false);
            deleteBtn.setAlpha(0.4f);
        }

        saveBtn.setOnClickListener(v -> save());

        deleteBtn.setOnClickListener(
                v -> {
                    if (existing == null) return;
                    if (serverId == null || serverId.trim().isEmpty()) return;
                    new AlertDialog.Builder(this)
                            .setTitle("Delete?")
                            .setMessage(existing.effectiveName())
                            .setPositiveButton(
                                    getString(R.string.delete),
                                    (d, w) -> {
                                        try {
                                            ServerStore.delete(getApplicationContext(), serverId);
                                            Toast.makeText(this, "Deleted", Toast.LENGTH_SHORT).show();
                                            finish();
                                        } catch (JSONException e) {
                                            Toast.makeText(
                                                            this,
                                                            "Delete failed: " + e.getMessage(),
                                                            Toast.LENGTH_LONG)
                                                    .show();
                                        }
                                    })
                            .setNegativeButton("Cancel", null)
                            .show();
                });
    }

    private void save() {
        ServerConfig ex = existing;

        String baseUrl = EmbyApi.normalizeBaseUrl(readText(baseUrlInput));
        String username = readText(usernameInput);
        String password = readTextRaw(passwordInput);

        if (ex != null) {
            if (baseUrl.isEmpty()) baseUrl = safe(ex.baseUrl);
            if (username.isEmpty()) username = safe(ex.username);
            if (password.isEmpty()) password = ex.password != null ? ex.password : "";
        }

        if (baseUrl.isEmpty()) {
            Toast.makeText(this, "Missing base url", Toast.LENGTH_LONG).show();
            return;
        }
        if (username.trim().isEmpty()) {
            Toast.makeText(this, "Missing username", Toast.LENGTH_LONG).show();
            return;
        }

        String displayName = readText(displayNameInput);
        String remark = readTextRaw(remarkInput);
        String iconUrl = readText(iconUrlInput);
        String lineName = readText(lineNameInput);

        List<ServerLine> baseLines = Collections.singletonList(new ServerLine(lineName, baseUrl));
        List<ServerLine> extraLines = parseLinesText(readTextRaw(linesTextInput));
        List<ServerLine> lines = mergeLines(baseLines, extraLines);

        boolean activate = activateCheckbox != null && activateCheckbox.isChecked();

        boolean needLogin =
                ex == null
                        || safe(ex.apiKey).isEmpty()
                        || !safe(ex.baseUrl).equals(baseUrl)
                        || !safe(ex.username).equals(username)
                        || !safePassword(ex.password).equals(password);

        if (!needLogin) {
            try {
                ServerConfig updated =
                        new ServerConfig(
                                serverId,
                                "emby",
                                baseUrl,
                                ex.apiKey,
                                username,
                                password,
                                displayName.isEmpty() ? safe(ex.displayName) : displayName,
                                remark,
                                iconUrl,
                                lines);
                ServerStore.upsert(getApplicationContext(), updated, activate);
                Toast.makeText(this, "Saved", Toast.LENGTH_SHORT).show();
                finish();
            } catch (JSONException e) {
                Toast.makeText(this, "Save failed: " + e.getMessage(), Toast.LENGTH_LONG).show();
            }
            return;
        }

        if (saveBtn != null) saveBtn.setEnabled(false);
        Toast.makeText(this, "Logging in...", Toast.LENGTH_SHORT).show();

        String finalUsername = username;
        String finalPassword = password;
        String finalDisplayName = displayName;
        String finalRemark = remark;
        String finalIconUrl = iconUrl;
        String finalLineName = lineName;
        String baseUrlForLogin = baseUrl;

        new Thread(
                        () -> {
                            try {
                                EmbyApi.LoginResult login =
                                        EmbyApi.authenticateByName(
                                                getApplicationContext(),
                                                baseUrlForLogin,
                                                finalUsername,
                                                finalPassword);
                                String token = login != null ? login.accessToken : "";
                                String resolvedBase = login != null ? login.baseUrl : baseUrlForLogin;
                                if (token.isEmpty()) throw new IllegalStateException("missing token");

                                String resolvedName = finalDisplayName;
                                if (resolvedName == null || resolvedName.trim().isEmpty()) {
                                    try {
                                        resolvedName =
                                                EmbyApi.fetchServerName(
                                                        getApplicationContext(), resolvedBase, token);
                                    } catch (Exception ignored) {
                                        // best-effort
                                    }
                                }
                                if (resolvedName == null) resolvedName = "";

                                List<ServerLine> baseLine =
                                        Collections.singletonList(
                                                new ServerLine(finalLineName, resolvedBase));
                                List<ServerLine> merged = mergeLines(baseLine, extraLines);
                                try {
                                    List<ServerLine> synced =
                                            EmbyApi.fetchExtDomains(
                                                    getApplicationContext(), resolvedBase, token, true);
                                    merged = mergeLines(merged, synced);
                                } catch (Exception ignored) {
                                    // best-effort
                                }

                                ServerConfig updated =
                                        new ServerConfig(
                                                serverId,
                                                "emby",
                                                resolvedBase,
                                                token,
                                                finalUsername,
                                                finalPassword,
                                                resolvedName,
                                                finalRemark,
                                                finalIconUrl,
                                                merged);
                                ServerStore.upsert(getApplicationContext(), updated, activate);
                                runOnUiThread(
                                        () -> {
                                            Toast.makeText(this, "Saved", Toast.LENGTH_SHORT).show();
                                            finish();
                                        });
                            } catch (Exception e) {
                                runOnUiThread(
                                        () -> {
                                            if (saveBtn != null) saveBtn.setEnabled(true);
                                            Toast.makeText(
                                                            this,
                                                            "Save failed: " + String.valueOf(e.getMessage()),
                                                            Toast.LENGTH_LONG)
                                                    .show();
                                        });
                            }
                        },
                        "tv-legacy-server-save")
                .start();
    }

    private static String readText(EditText input) {
        if (input == null || input.getText() == null) return "";
        return input.getText().toString().trim();
    }

    private static String readTextRaw(EditText input) {
        if (input == null || input.getText() == null) return "";
        return input.getText().toString();
    }

    private static String safe(String s) {
        return s != null ? s.trim() : "";
    }

    private static String safePassword(String s) {
        return s != null ? s : "";
    }

    private static String findActiveLineName(ServerConfig cfg) {
        if (cfg == null) return "";
        String base = safe(cfg.baseUrl);
        List<ServerLine> lines = cfg.lines;
        if (lines == null || lines.isEmpty()) return "";
        for (int i = 0; i < lines.size(); i++) {
            ServerLine l = lines.get(i);
            if (l == null) continue;
            String u = safe(l.url);
            if (u.isEmpty()) continue;
            if (u.equals(base)) return safe(l.name);
        }
        return "";
    }

    private static String buildOtherLinesText(ServerConfig cfg) {
        if (cfg == null) return "";
        String base = safe(cfg.baseUrl);
        List<ServerLine> lines = cfg.lines;
        if (lines == null || lines.isEmpty()) return "";

        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < lines.size(); i++) {
            ServerLine l = lines.get(i);
            if (l == null) continue;
            String u = safe(l.url);
            if (u.isEmpty() || u.equals(base)) continue;
            String n = safe(l.name);
            if (sb.length() > 0) sb.append("\n");
            if (!n.isEmpty()) {
                sb.append(n).append("|").append(u);
            } else {
                sb.append(u);
            }
        }
        return sb.toString();
    }

    private static List<ServerLine> parseLinesText(String text) {
        String t = text != null ? text.trim() : "";
        if (t.isEmpty()) return Collections.emptyList();
        String[] rows = t.split("\\r?\\n");
        List<ServerLine> out = new ArrayList<>();
        for (int i = 0; i < rows.length; i++) {
            String row = rows[i] != null ? rows[i].trim() : "";
            if (row.isEmpty()) continue;
            if (row.startsWith("#")) continue;

            String name = "";
            String url = row;
            if (row.contains("|")) {
                String[] parts = row.split("\\|", 2);
                name = parts.length > 0 ? parts[0].trim() : "";
                url = parts.length > 1 ? parts[1].trim() : "";
            }
            String u = EmbyApi.normalizeBaseUrl(url);
            if (u.isEmpty()) continue;
            out.add(new ServerLine(name, u));
        }
        return Collections.unmodifiableList(out);
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
            String u = safe(l.url);
            if (u.isEmpty()) continue;

            ServerLine existing = map.get(u);
            if (existing == null) {
                map.put(u, l);
                continue;
            }

            String existingName = safe(existing.name);
            String name = safe(l.name);
            if (existingName.isEmpty() && !name.isEmpty()) {
                map.put(u, new ServerLine(name, u));
            }
        }
    }
}
