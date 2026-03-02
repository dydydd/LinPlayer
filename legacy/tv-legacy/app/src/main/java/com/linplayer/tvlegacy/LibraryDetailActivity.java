package com.linplayer.tvlegacy;

import android.graphics.Bitmap;
import android.os.Bundle;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.TextView;
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

public final class LibraryDetailActivity extends AppCompatActivity {
    static final String EXTRA_VIEW_ID = "view_id";
    static final String EXTRA_VIEW_NAME = "view_name";

    private ImageView bgImage;
    @Nullable private Bitmap bgOriginal;

    private EmbyCardAdapter gridAdapter;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_library_detail);

        bgImage = findViewById(R.id.bg_image);
        loadBackground();

        String viewId = getIntent().getStringExtra(EXTRA_VIEW_ID);
        String viewName = getIntent().getStringExtra(EXTRA_VIEW_NAME);
        if (viewId == null || viewId.trim().isEmpty()) {
            Toast.makeText(this, "Missing library id", Toast.LENGTH_LONG).show();
            finish();
            return;
        }

        TextView title = findViewById(R.id.library_title);
        title.setText(viewName != null && !viewName.trim().isEmpty() ? viewName.trim() : "媒体库");

        int alpha255 = TvStyle.panelAlpha255(this);
        TvStyle.applyPanelAlpha(findViewById(R.id.btn_back), alpha255);

        ImageButton backBtn = findViewById(R.id.btn_back);
        backBtn.setOnClickListener(v -> finish());

        RecyclerView grid = findViewById(R.id.library_grid);
        int spanCount = 5;
        grid.setLayoutManager(new GridLayoutManager(this, spanCount));
        grid.addItemDecoration(new GridSpacingItemDecoration(spanCount, dpToPx(12), true));
        grid.setItemAnimator(null);

        gridAdapter = new EmbyCardAdapter(item -> EmbyNav.openItem(this, item));
        gridAdapter.setData(Collections.emptyList(), EmbyCardAdapter.MODE_NORMAL, 0, alpha255);
        grid.setAdapter(gridAdapter);

        loadItems(viewId);
    }

    private void loadItems(String viewId) {
        ServerConfig active = ServerStore.getActive(this);
        if (active == null || safe(active.baseUrl).isEmpty() || safe(active.apiKey).isEmpty()) {
            Toast.makeText(this, "请先配置服务器", Toast.LENGTH_LONG).show();
            return;
        }

        EmbyClient client =
                new EmbyClient(this, active.baseUrl, active.apiPrefix, active.apiKey, active.userId);
        new Thread(
                        () -> {
                            try {
                                List<EmbyItem> items = client.listItemsByView(viewId, 200);
                                runOnUiThread(
                                        () -> {
                                            int alpha255 = TvStyle.panelAlpha255(this);
                                            gridAdapter.setData(
                                                    items, EmbyCardAdapter.MODE_NORMAL, 0, alpha255);
                                        });
                            } catch (Exception e) {
                                runOnUiThread(
                                        () ->
                                                Toast.makeText(
                                                                this,
                                                                "Load failed: "
                                                                        + String.valueOf(e.getMessage()),
                                                                Toast.LENGTH_LONG)
                                                        .show());
                            }
                        },
                        "tv-legacy-library")
                .start();
    }

    private void loadBackground() {
        new Thread(
                        () -> {
                            try {
                                String url = "https://bing.img.run/rand_uhd.php?t=" + System.currentTimeMillis();
                                int screenMax =
                                        Math.max(
                                                getResources().getDisplayMetrics().widthPixels,
                                                getResources().getDisplayMetrics().heightPixels);
                                int max = Math.min(screenMax, 1920);
                                Bitmap bmp = BitmapFetcher.fetch(getApplicationContext(), url, max);
                                if (bmp == null) return;
                                bgOriginal = bmp;
                                applyBackgroundBlur();
                            } catch (Throwable ignored) {
                                // ignore
                            }
                        },
                        "tv-legacy-bg-library")
                .start();
    }

    private void applyBackgroundBlur() {
        Bitmap original = bgOriginal;
        if (original == null || bgImage == null) return;
        int radius = TvStyle.backgroundBlurRadius(this);
        Bitmap blurred = null;
        try {
            blurred = blurForBackground(original, radius);
        } catch (Throwable ignored) {
            blurred = null;
        }
        Bitmap result = blurred;
        runOnUiThread(
                () -> {
                    if (isFinishing() || isDestroyed()) return;
                    if (bgImage != null) {
                        bgImage.setImageBitmap(result != null ? result : original);
                    }
                });
    }

    @Nullable
    private static Bitmap blurForBackground(Bitmap original, int radius) {
        if (original == null) return null;
        int r = Math.max(0, radius);
        if (r <= 0) return original;

        try {
            int w = Math.max(1, original.getWidth() / 4);
            int h = Math.max(1, original.getHeight() / 4);
            Bitmap small = Bitmap.createScaledBitmap(original, w, h, true);
            Bitmap blurredSmall = BitmapBlur.blur(small, r);
            if (blurredSmall == null) return original;
            return Bitmap.createScaledBitmap(
                    blurredSmall, original.getWidth(), original.getHeight(), true);
        } catch (Throwable ignored) {
            return original;
        }
    }

    private int dpToPx(int dp) {
        float density = getResources().getDisplayMetrics().density;
        return Math.round(dp * density);
    }

    private static String safe(String s) {
        return s != null ? s.trim() : "";
    }
}
