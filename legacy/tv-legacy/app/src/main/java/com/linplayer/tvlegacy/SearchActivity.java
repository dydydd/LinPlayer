package com.linplayer.tvlegacy;

import android.graphics.Bitmap;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.Toast;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.GridLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.linplayer.tvlegacy.emby.EmbyClient;
import com.linplayer.tvlegacy.emby.EmbyItem;
import com.linplayer.tvlegacy.servers.ServerConfig;
import com.linplayer.tvlegacy.servers.ServerStore;
import java.util.Collections;
import java.util.List;

public final class SearchActivity extends AppCompatActivity {
    private ImageView bgImage;
    @Nullable private Bitmap bgOriginal;

    private EditText input;
    private EmbyCardAdapter resultsAdapter;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_search);

        bgImage = findViewById(R.id.bg_image);
        loadBackground();

        int alpha255 = TvStyle.panelAlpha255(this);
        TvStyle.applyPanelAlpha(findViewById(R.id.btn_back), alpha255);
        TvStyle.applyPanelAlpha(findViewById(R.id.search_input), alpha255);
        TvStyle.applyPanelAlpha(findViewById(R.id.btn_do_search), alpha255);

        ImageButton backBtn = findViewById(R.id.btn_back);
        backBtn.setOnClickListener(v -> finish());

        input = findViewById(R.id.search_input);
        input.setOnEditorActionListener(
                (v, actionId, event) -> {
                    boolean enter =
                            (event != null
                                            && event.getAction() == KeyEvent.ACTION_DOWN
                                            && event.getKeyCode() == KeyEvent.KEYCODE_ENTER)
                                    || actionId == EditorInfo.IME_ACTION_SEARCH;
                    if (enter) {
                        doSearch();
                        return true;
                    }
                    return false;
                });

        Button searchBtn = findViewById(R.id.btn_do_search);
        searchBtn.setOnClickListener(v -> doSearch());

        RecyclerView results = findViewById(R.id.search_results);
        int spanCount = 5;
        results.setLayoutManager(new GridLayoutManager(this, spanCount));
        results.addItemDecoration(new GridSpacingItemDecoration(spanCount, dpToPx(12), true));

        resultsAdapter = new EmbyCardAdapter(item -> EmbyNav.openItem(this, item));
        resultsAdapter.setData(Collections.emptyList(), EmbyCardAdapter.MODE_NORMAL, 0, alpha255);
        results.setAdapter(resultsAdapter);
    }

    private void doSearch() {
        String q = input != null ? safe(input.getText() != null ? input.getText().toString() : "") : "";
        if (q.isEmpty()) {
            Toast.makeText(this, "请输入搜索关键词", Toast.LENGTH_SHORT).show();
            return;
        }

        ServerConfig active = ServerStore.getActive(this);
        if (active == null || safe(active.baseUrl).isEmpty() || safe(active.apiKey).isEmpty()) {
            Toast.makeText(this, "请先配置服务器", Toast.LENGTH_LONG).show();
            return;
        }

        EmbyClient client = new EmbyClient(this, active.baseUrl, active.apiKey);
        new Thread(
                        () -> {
                            try {
                                List<EmbyItem> items = client.search(q, 80);
                                runOnUiThread(
                                        () -> {
                                            int alpha255 = TvStyle.panelAlpha255(this);
                                            resultsAdapter.setData(
                                                    items, EmbyCardAdapter.MODE_NORMAL, 0, alpha255);
                                        });
                            } catch (Exception e) {
                                runOnUiThread(
                                        () ->
                                                Toast.makeText(
                                                                this,
                                                                "Search failed: "
                                                                        + String.valueOf(e.getMessage()),
                                                                Toast.LENGTH_LONG)
                                                        .show());
                            }
                        },
                        "tv-legacy-search")
                .start();
    }

    private void loadBackground() {
        new Thread(
                        () -> {
                            try {
                                String url = "https://bing.img.run/rand_uhd.php?t=" + System.currentTimeMillis();
                                int max = Math.max(getResources().getDisplayMetrics().widthPixels, getResources().getDisplayMetrics().heightPixels);
                                Bitmap bmp = BitmapFetcher.fetch(getApplicationContext(), url, max);
                                if (bmp == null) return;
                                bgOriginal = bmp;
                                applyBackgroundBlur();
                            } catch (Exception ignored) {
                                // ignore
                            }
                        },
                        "tv-legacy-bg-search")
                .start();
    }

    private void applyBackgroundBlur() {
        Bitmap original = bgOriginal;
        if (original == null || bgImage == null) return;
        int radius = TvStyle.backgroundBlurRadius(this);
        Bitmap blurred = blurForBackground(original, radius);
        runOnUiThread(
                () -> {
                    if (isFinishing() || isDestroyed()) return;
                    if (bgImage != null) bgImage.setImageBitmap(blurred != null ? blurred : original);
                });
    }

    @Nullable
    private static Bitmap blurForBackground(Bitmap original, int radius) {
        if (original == null) return null;
        int r = Math.max(0, radius);
        if (r <= 0) return original;

        int w = Math.max(1, original.getWidth() / 4);
        int h = Math.max(1, original.getHeight() / 4);
        Bitmap small = Bitmap.createScaledBitmap(original, w, h, true);
        Bitmap blurredSmall = BitmapBlur.blur(small, r);
        if (blurredSmall == null) return original;
        return Bitmap.createScaledBitmap(blurredSmall, original.getWidth(), original.getHeight(), true);
    }

    private int dpToPx(int dp) {
        float density = getResources().getDisplayMetrics().density;
        return Math.round(dp * density);
    }

    private static String safe(String s) {
        return s != null ? s.trim() : "";
    }
}
