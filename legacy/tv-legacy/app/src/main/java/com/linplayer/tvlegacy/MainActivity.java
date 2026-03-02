package com.linplayer.tvlegacy;

import android.content.Intent;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.view.View;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.GridLayoutManager;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.linplayer.tvlegacy.emby.EmbyClient;
import com.linplayer.tvlegacy.emby.EmbyItem;
import com.linplayer.tvlegacy.emby.EmbyView;
import com.linplayer.tvlegacy.servers.ServerConfig;
import com.linplayer.tvlegacy.servers.ServerStore;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class MainActivity extends AppCompatActivity {
    private enum Tab {
        HOME,
        FAVORITES
    }

    private enum FavType {
        SERIES,
        MOVIE,
        EPISODE
    }

    private ImageView bgImage;
    @Nullable private Bitmap bgOriginal;

    private LinearLayout serverBtn;
    private ImageView serverIconImg;
    private TextView serverIconText;
    private TextView serverName;

    private TextView tabHome;
    private TextView tabFavorites;
    private View tabContainer;

    private ImageButton searchBtn;
    private ImageButton styleBtn;

    private RecyclerView homeSectionList;
    private HomeSectionAdapter homeAdapter;

    private View favoritesRoot;
    private View favoritesFilterRow;
    private TextView favFilterSeries;
    private TextView favFilterMovies;
    private TextView favFilterEpisodes;
    private RecyclerView favoritesGrid;
    private EmbyCardAdapter favoritesAdapter;
    private List<EmbyItem> favoriteItems = Collections.emptyList();

    private Tab currentTab = Tab.HOME;
    private FavType currentFavType = FavType.SERIES;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        if (!ServerStore.hasAny(this)) {
            Intent i = new Intent(this, ServersActivity.class);
            i.putExtra(ServersActivity.EXTRA_REQUIRE_ONE, true);
            startActivity(i);
            finish();
            return;
        }

        setContentView(R.layout.activity_home);

        bgImage = findViewById(R.id.bg_image);
        loadBackground();

        serverBtn = findViewById(R.id.btn_server);
        serverIconImg = findViewById(R.id.server_icon_img);
        serverIconText = findViewById(R.id.server_icon_text);
        serverName = findViewById(R.id.server_name);

        tabContainer = findViewById(R.id.tab_container);
        tabHome = findViewById(R.id.tab_home);
        tabFavorites = findViewById(R.id.tab_favorites);

        searchBtn = findViewById(R.id.btn_search);
        styleBtn = findViewById(R.id.btn_style);

        homeSectionList = findViewById(R.id.home_section_list);
        homeSectionList.setLayoutManager(new LinearLayoutManager(this));
        homeSectionList.setItemAnimator(null);
        homeAdapter =
                new HomeSectionAdapter(
                        new HomeSectionAdapter.Listener() {
                            @Override
                            public void onItemClicked(EmbyItem item) {
                                EmbyNav.openItem(MainActivity.this, item);
                            }

                            @Override
                            public void onViewClicked(EmbyView view) {
                                EmbyNav.openView(MainActivity.this, view);
                            }
                        });
        homeSectionList.setAdapter(homeAdapter);

        favoritesRoot = findViewById(R.id.favorites_root);
        favoritesFilterRow = findViewById(R.id.favorites_filter_row);
        favFilterSeries = findViewById(R.id.fav_filter_series);
        favFilterMovies = findViewById(R.id.fav_filter_movies);
        favFilterEpisodes = findViewById(R.id.fav_filter_episodes);
        favoritesGrid = findViewById(R.id.favorites_grid);
        int spanCount = 5;
        favoritesGrid.setLayoutManager(new GridLayoutManager(this, spanCount));
        favoritesGrid.setItemAnimator(null);
        favoritesGrid.addItemDecoration(new GridSpacingItemDecoration(spanCount, dpToPx(12), true));
        favoritesAdapter = new EmbyCardAdapter(item -> EmbyNav.openItem(this, item));
        favoritesGrid.setAdapter(favoritesAdapter);

        serverBtn.setOnClickListener(v -> showServerSwitchDialog());
        serverBtn.setOnLongClickListener(
                v -> {
                    startActivity(new Intent(this, ServersActivity.class));
                    return true;
                });

        tabHome.setOnClickListener(v -> setTab(Tab.HOME));
        tabFavorites.setOnClickListener(v -> setTab(Tab.FAVORITES));

        searchBtn.setOnClickListener(v -> startActivity(new Intent(this, SearchActivity.class)));

        styleBtn.setOnClickListener(v -> showStyleDialog());
        styleBtn.setOnLongClickListener(
                v -> {
                    startActivity(new Intent(this, SettingsActivity.class));
                    return true;
                });

        favFilterSeries.setOnClickListener(v -> setFavType(FavType.SERIES));
        favFilterMovies.setOnClickListener(v -> setFavType(FavType.MOVIE));
        favFilterEpisodes.setOnClickListener(v -> setFavType(FavType.EPISODE));

        setTab(Tab.HOME);
        setFavType(FavType.SERIES);

        applyStyle();

        if (AppPrefs.isProxyEnabled(this)) {
            ProxyService.start(this);
        } else {
            ProxyEnv.disable();
        }
    }

    @Override
    protected void onStart() {
        super.onStart();
        refreshActiveServerUi();
        loadHomeData();
        if (currentTab == Tab.FAVORITES) {
            loadFavorites();
        }
    }

    private void setTab(Tab tab) {
        currentTab = tab != null ? tab : Tab.HOME;
        boolean home = currentTab == Tab.HOME;

        homeSectionList.setVisibility(home ? View.VISIBLE : View.GONE);
        favoritesRoot.setVisibility(home ? View.GONE : View.VISIBLE);

        if (home) {
            setSelectedPill(tabHome, tabFavorites);
        } else {
            setSelectedPill(tabFavorites, tabHome);
            loadFavorites();
        }
        applyStyle();
    }

    private void setFavType(FavType type) {
        currentFavType = type != null ? type : FavType.SERIES;
        if (currentFavType == FavType.SERIES) {
            setSelectedPill(favFilterSeries, favFilterMovies, favFilterEpisodes);
        } else if (currentFavType == FavType.MOVIE) {
            setSelectedPill(favFilterMovies, favFilterSeries, favFilterEpisodes);
        } else {
            setSelectedPill(favFilterEpisodes, favFilterSeries, favFilterMovies);
        }
        if (currentTab == Tab.FAVORITES) {
            loadFavorites();
        }
        applyStyle();
    }

    private void refreshActiveServerUi() {
        ServerConfig active = ServerStore.getActive(this);
        if (active == null) return;
        String name = active.effectiveName();
        serverName.setText(name);

        String iconUrl = safe(active.iconUrl);
        if (!iconUrl.isEmpty()) {
            serverIconText.setVisibility(View.GONE);
            serverIconImg.setVisibility(View.VISIBLE);
            ImageLoader.load(serverIconImg, iconUrl, 96);
        } else {
            serverIconImg.setVisibility(View.GONE);
            serverIconImg.setImageDrawable(null);
            serverIconText.setVisibility(View.VISIBLE);
            serverIconText.setText(avatarLetter(name));
        }
    }

    private void loadHomeData() {
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
                                List<HomeSection> sections = new ArrayList<>();
                                List<EmbyItem> resume = client.listResume(20);
                                if (resume != null && !resume.isEmpty()) {
                                    sections.add(HomeSection.resume("观看记录", resume));
                                }

                                List<EmbyView> views = client.listViews();
                                sections.add(HomeSection.views("媒体库", views));

                                if (views != null) {
                                    for (int i = 0; i < views.size(); i++) {
                                        EmbyView v = views.get(i);
                                        if (v == null || safe(v.id).isEmpty()) continue;
                                        List<EmbyItem> items = client.listItemsByView(v.id, 10);
                                        if (items == null) items = Collections.emptyList();
                                        sections.add(HomeSection.viewItems(v.name, items));
                                    }
                                }

                                List<HomeSection> out = Collections.unmodifiableList(sections);
                                runOnUiThread(
                                        () -> {
                                            if (isFinishing() || isDestroyed()) return;
                                            homeAdapter.setSections(out);
                                        });
                            } catch (Exception e) {
                                runOnUiThread(
                                        () -> {
                                            if (isFinishing() || isDestroyed()) return;
                                            Toast.makeText(
                                                            this,
                                                            "Load failed: "
                                                                    + String.valueOf(e.getMessage()),
                                                            Toast.LENGTH_LONG)
                                                    .show();
                                        });
                            }
                        },
                        "tv-legacy-home")
                .start();
    }

    private void loadFavorites() {
        if (currentTab != Tab.FAVORITES) return;
        ServerConfig active = ServerStore.getActive(this);
        if (active == null || safe(active.baseUrl).isEmpty() || safe(active.apiKey).isEmpty()) {
            Toast.makeText(this, "请先配置服务器", Toast.LENGTH_LONG).show();
            return;
        }

        String type =
                currentFavType == FavType.SERIES
                        ? "Series"
                        : (currentFavType == FavType.MOVIE ? "Movie" : "Episode");

        EmbyClient client =
                new EmbyClient(this, active.baseUrl, active.apiPrefix, active.apiKey, active.userId);
        new Thread(
                        () -> {
                            try {
                                List<EmbyItem> items = client.listFavorites(type, 200);
                                runOnUiThread(
                                        () -> {
                                            if (isFinishing() || isDestroyed()) return;
                                            favoriteItems = items != null ? items : Collections.emptyList();
                                            int alpha255 = TvStyle.panelAlpha255(this);
                                            favoritesAdapter.setData(
                                                    favoriteItems,
                                                    EmbyCardAdapter.MODE_NORMAL,
                                                    0,
                                                    alpha255);
                                        });
                            } catch (Exception e) {
                                runOnUiThread(
                                        () ->
                                                Toast.makeText(
                                                                this,
                                                                "Load favorites failed: "
                                                                        + String.valueOf(e.getMessage()),
                                                                Toast.LENGTH_LONG)
                                                        .show());
                            }
                        },
                        "tv-legacy-favorites")
                .start();
    }

    private void showServerSwitchDialog() {
        List<ServerConfig> all = ServerStore.list(this);
        ServerConfig active = ServerStore.getActive(this);
        String activeId = active != null ? safe(active.id) : "";

        List<ServerConfig> current =
                active != null ? Collections.singletonList(active) : Collections.emptyList();
        List<ServerConfig> others = new ArrayList<>();
        if (all != null) {
            for (int i = 0; i < all.size(); i++) {
                ServerConfig c = all.get(i);
                if (c == null) continue;
                if (!activeId.isEmpty() && activeId.equals(safe(c.id))) continue;
                others.add(c);
            }
        }

        View v = getLayoutInflater().inflate(R.layout.dialog_server_switch, null);
        RecyclerView currentList = v.findViewById(R.id.current_server_list);
        RecyclerView otherList = v.findViewById(R.id.other_server_list);

        currentList.setLayoutManager(new LinearLayoutManager(this));
        otherList.setLayoutManager(new LinearLayoutManager(this));
        currentList.setItemAnimator(null);
        otherList.setItemAnimator(null);

        int alpha255 = TvStyle.panelAlpha255(this);

        AlertDialog dlg = new AlertDialog.Builder(this).setTitle("服务器").setView(v).setNegativeButton("关闭", null).create();

        ServerChipAdapter.Listener onClick =
                server -> {
                    if (server == null || safe(server.id).isEmpty()) return;
                    ServerStore.setActive(getApplicationContext(), server.id);
                    dlg.dismiss();
                    refreshActiveServerUi();
                    loadHomeData();
                    favoriteItems = Collections.emptyList();
                    favoritesAdapter.setData(favoriteItems, EmbyCardAdapter.MODE_NORMAL, 0, alpha255);
                    if (currentTab == Tab.FAVORITES) {
                        loadFavorites();
                    }
                };

        ServerChipAdapter currentAdapter = new ServerChipAdapter(onClick);
        currentAdapter.setData(current, alpha255);
        currentList.setAdapter(currentAdapter);

        ServerChipAdapter otherAdapter = new ServerChipAdapter(onClick);
        otherAdapter.setData(others, alpha255);
        otherList.setAdapter(otherAdapter);

        dlg.show();
    }

    private void showStyleDialog() {
        View v = getLayoutInflater().inflate(R.layout.dialog_style, null);
        TextView alphaTitle = v.findViewById(R.id.style_alpha_title);
        TextView blurTitle = v.findViewById(R.id.style_blur_title);
        SeekBar alphaSeek = v.findViewById(R.id.style_alpha_seek);
        SeekBar blurSeek = v.findViewById(R.id.style_blur_seek);

        int alphaPercent = AppPrefs.getUiPanelAlphaPercent(this);
        int blurRadius = AppPrefs.getUiBackgroundBlur(this);
        alphaSeek.setProgress(alphaPercent);
        blurSeek.setProgress(blurRadius);
        alphaTitle.setText("透明度  " + alphaPercent + "%");
        blurTitle.setText("模糊度  " + blurRadius);

        alphaSeek.setOnSeekBarChangeListener(
                new SeekBar.OnSeekBarChangeListener() {
                    @Override
                    public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                        int p = clamp(progress, 5, 90);
                        alphaTitle.setText("透明度  " + p + "%");
                        previewPanelAlpha(p);
                    }

                    @Override
                    public void onStartTrackingTouch(SeekBar seekBar) {}

                    @Override
                    public void onStopTrackingTouch(SeekBar seekBar) {}
                });

        blurSeek.setOnSeekBarChangeListener(
                new SeekBar.OnSeekBarChangeListener() {
                    @Override
                    public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                        int r = clamp(progress, 0, 24);
                        blurTitle.setText("模糊度  " + r);
                    }

                    @Override
                    public void onStartTrackingTouch(SeekBar seekBar) {}

                    @Override
                    public void onStopTrackingTouch(SeekBar seekBar) {}
                });

        new AlertDialog.Builder(this)
                .setTitle("样式")
                .setView(v)
                .setPositiveButton(
                        "保存",
                        (d, w) -> {
                            int p = clamp(alphaSeek.getProgress(), 5, 90);
                            int r = clamp(blurSeek.getProgress(), 0, 24);
                            AppPrefs.setUiPanelAlphaPercent(getApplicationContext(), p);
                            AppPrefs.setUiBackgroundBlur(getApplicationContext(), r);
                            applyStyle();
                            applyBackgroundBlur();
                        })
                .setNegativeButton("取消", null)
                .show();
    }

    private void previewPanelAlpha(int alphaPercent) {
        int alpha255 = Math.round(255f * (clamp(alphaPercent, 5, 90) / 100f));
        applyPanelAlpha(alpha255);
    }

    private void applyStyle() {
        int alpha255 = TvStyle.panelAlpha255(this);
        applyPanelAlpha(alpha255);
        homeAdapter.setPanelAlpha255(alpha255);
        favoritesAdapter.setData(favoriteItems, EmbyCardAdapter.MODE_NORMAL, 0, alpha255);
    }

    private void applyPanelAlpha(int alpha255) {
        TvStyle.applyPanelAlpha(serverBtn, alpha255);
        TvStyle.applyPanelAlpha(searchBtn, alpha255);
        TvStyle.applyPanelAlpha(styleBtn, alpha255);
        TvStyle.applyPanelAlpha(tabContainer, alpha255);
        TvStyle.applyPanelAlpha(favoritesFilterRow, alpha255);

        TvStyle.applyPanelAlpha(tabHome, alpha255);
        TvStyle.applyPanelAlpha(tabFavorites, alpha255);
        TvStyle.applyPanelAlpha(favFilterSeries, alpha255);
        TvStyle.applyPanelAlpha(favFilterMovies, alpha255);
        TvStyle.applyPanelAlpha(favFilterEpisodes, alpha255);
    }

    private void setSelectedPill(TextView selected, TextView... others) {
        if (selected != null) {
            selected.setBackgroundResource(R.drawable.tv_tab_selected_bg);
            selected.setTextColor(0xFF000000);
        }
        if (others != null) {
            for (int i = 0; i < others.length; i++) {
                TextView o = others[i];
                if (o == null) continue;
                o.setBackgroundDrawable(null);
                o.setTextColor(0xFFFFFFFF);
            }
        }
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
                        "tv-legacy-bg-home")
                .start();
    }

    private void applyBackgroundBlur() {
        Bitmap original = bgOriginal;
        if (original == null || bgImage == null) return;
        int radius = TvStyle.backgroundBlurRadius(this);
        new Thread(
                        () -> {
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
                                            bgImage.setImageBitmap(
                                                    result != null ? result : original);
                                        }
                                    });
                        },
                        "tv-legacy-bg-blur")
                .start();
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

    private static String avatarLetter(String name) {
        String n = safe(name);
        if (n.isEmpty()) return "?";
        return n.substring(0, 1).toUpperCase();
    }

    private static int clamp(int v, int min, int max) {
        return v < min ? min : (v > max ? max : v);
    }
}
