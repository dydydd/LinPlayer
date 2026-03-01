package com.linplayer.tvlegacy;

import android.content.Intent;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.linplayer.tvlegacy.emby.EmbyClient;
import com.linplayer.tvlegacy.emby.EmbyEpisode;
import com.linplayer.tvlegacy.emby.EmbyItemDetails;
import com.linplayer.tvlegacy.emby.EmbySeason;
import com.linplayer.tvlegacy.servers.ServerConfig;
import com.linplayer.tvlegacy.servers.ServerStore;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

public final class ItemDetailActivity extends AppCompatActivity {
    static final String EXTRA_ITEM_ID = "item_id";
    static final String EXTRA_ITEM_TYPE = "item_type";
    static final String EXTRA_POSITION_MS = "position_ms";

    private String itemId = "";
    private String itemType = "";
    private long initialPositionMs = 0L;

    @Nullable private EmbyClient client;
    @Nullable private EmbyItemDetails itemDetails;

    private boolean favorite = false;
    private boolean played = false;

    @Nullable private ImageView backdropView;
    @Nullable private ImageView posterView;
    @Nullable private TextView titleText;
    @Nullable private TextView metaText;
    @Nullable private TextView overviewText;
    @Nullable private Button playBtn;
    @Nullable private Button favoriteBtn;
    @Nullable private Button playedBtn;

    @Nullable private View seasonSection;
    @Nullable private EditText seasonInput;
    @Nullable private RecyclerView seasonList;
    @Nullable private SeasonChipAdapter seasonAdapter;
    private List<EmbySeason> seasons = Collections.emptyList();
    private int selectedSeasonPos = -1;

    @Nullable private View episodeSection;
    @Nullable private EditText episodeInput;
    @Nullable private RecyclerView episodeList;
    @Nullable private EpisodeChipAdapter episodeAdapter;
    private List<EmbyEpisode> episodes = Collections.emptyList();
    private int selectedEpisodePos = -1;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_item_detail);

        itemId = safe(getIntent().getStringExtra(EXTRA_ITEM_ID));
        itemType = safe(getIntent().getStringExtra(EXTRA_ITEM_TYPE));
        initialPositionMs = Math.max(0L, getIntent().getLongExtra(EXTRA_POSITION_MS, 0L));

        if (itemId.isEmpty()) {
            Toast.makeText(this, "Missing item id", Toast.LENGTH_LONG).show();
            finish();
            return;
        }

        ServerConfig active = ServerStore.getActive(this);
        if (active == null || safe(active.baseUrl).isEmpty() || safe(active.apiKey).isEmpty()) {
            Toast.makeText(this, "Missing server config", Toast.LENGTH_LONG).show();
            finish();
            return;
        }
        client = new EmbyClient(this, active.baseUrl, active.apiPrefix, active.apiKey, active.userId);
        if (client == null || !client.isConfigured()) {
            Toast.makeText(this, "Server not configured", Toast.LENGTH_LONG).show();
            finish();
            return;
        }

        backdropView = findViewById(R.id.detail_backdrop);
        posterView = findViewById(R.id.detail_poster);
        titleText = findViewById(R.id.detail_title);
        metaText = findViewById(R.id.detail_meta);
        overviewText = findViewById(R.id.detail_overview);
        playBtn = findViewById(R.id.btn_play);
        favoriteBtn = findViewById(R.id.btn_favorite);
        playedBtn = findViewById(R.id.btn_played);

        seasonSection = findViewById(R.id.season_section);
        seasonInput = findViewById(R.id.season_input);
        seasonList = findViewById(R.id.season_list);
        episodeSection = findViewById(R.id.episode_section);
        episodeInput = findViewById(R.id.episode_input);
        episodeList = findViewById(R.id.episode_list);

        if (titleText != null) titleText.setText("Loading...");
        if (metaText != null) metaText.setText("");
        if (overviewText != null) overviewText.setText("");

        if (seasonSection != null) seasonSection.setVisibility(View.GONE);
        if (episodeSection != null) episodeSection.setVisibility(View.GONE);

        if (playBtn != null) playBtn.setOnClickListener(v -> play());
        if (favoriteBtn != null) favoriteBtn.setOnClickListener(v -> toggleFavorite());
        if (playedBtn != null) playedBtn.setOnClickListener(v -> togglePlayed());

        setupSeasonUi();
        setupEpisodeUi();

        loadItem();
    }

    private void setupSeasonUi() {
        RecyclerView rv = seasonList;
        if (rv != null) {
            rv.setLayoutManager(new LinearLayoutManager(this, LinearLayoutManager.HORIZONTAL, false));
            rv.setItemAnimator(null);
            rv.addItemDecoration(new HorizontalSpacingItemDecoration(dpToPx(12), true));
            SeasonChipAdapter a = new SeasonChipAdapter(season -> selectSeason(season));
            seasonAdapter = a;
            rv.setAdapter(a);
            rv.post(() -> a.setItemWidthPx(computeSelectorItemWidthPx(rv, 8)));
        }

        EditText input = seasonInput;
        if (input != null) {
            input.setOnEditorActionListener(
                    (v, actionId, event) -> {
                        if (actionId == EditorInfo.IME_ACTION_DONE) {
                            handleSeasonInput();
                            return true;
                        }
                        return false;
                    });
            input.setOnKeyListener(
                    (v, keyCode, event) -> {
                        if (event == null || event.getAction() != KeyEvent.ACTION_UP) return false;
                        if (keyCode == KeyEvent.KEYCODE_ENTER
                                || keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER
                                || keyCode == KeyEvent.KEYCODE_DPAD_CENTER) {
                            handleSeasonInput();
                            return true;
                        }
                        return false;
                    });
        }
    }

    private void setupEpisodeUi() {
        RecyclerView rv = episodeList;
        if (rv != null) {
            rv.setLayoutManager(new LinearLayoutManager(this, LinearLayoutManager.HORIZONTAL, false));
            rv.setItemAnimator(null);
            rv.addItemDecoration(new HorizontalSpacingItemDecoration(dpToPx(12), true));
            EpisodeChipAdapter a = new EpisodeChipAdapter(episode -> selectEpisode(episode));
            episodeAdapter = a;
            rv.setAdapter(a);
            rv.post(() -> a.setItemWidthPx(computeSelectorItemWidthPx(rv, 6)));
        }

        EditText input = episodeInput;
        if (input != null) {
            input.setOnEditorActionListener(
                    (v, actionId, event) -> {
                        if (actionId == EditorInfo.IME_ACTION_DONE) {
                            handleEpisodeInput();
                            return true;
                        }
                        return false;
                    });
            input.setOnKeyListener(
                    (v, keyCode, event) -> {
                        if (event == null || event.getAction() != KeyEvent.ACTION_UP) return false;
                        if (keyCode == KeyEvent.KEYCODE_ENTER
                                || keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER
                                || keyCode == KeyEvent.KEYCODE_DPAD_CENTER) {
                            handleEpisodeInput();
                            return true;
                        }
                        return false;
                    });
        }
    }

    private void loadItem() {
        EmbyClient c = client;
        if (c == null) return;
        new Thread(
                        () -> {
                            try {
                                EmbyItemDetails details = c.getItemDetails(itemId);
                                if (details == null) throw new IllegalStateException("Missing item details");
                                runOnUiThread(
                                        () -> {
                                            if (isFinishing() || isDestroyed()) return;
                                            applyItem(details);
                                        });

                                if (details.isType("Series")) {
                                    List<EmbySeason> ss = c.listSeasons(details.id);
                                    runOnUiThread(
                                            () -> {
                                                if (isFinishing() || isDestroyed()) return;
                                                applySeasons(ss);
                                            });
                                }
                            } catch (Exception e) {
                                runOnUiThread(
                                        () ->
                                                Toast.makeText(
                                                                ItemDetailActivity.this,
                                                                "Load failed: " + String.valueOf(e.getMessage()),
                                                                Toast.LENGTH_LONG)
                                                        .show());
                            }
                        },
                        "tv-legacy-item-detail")
                .start();
    }

    private void applyItem(EmbyItemDetails details) {
        itemDetails = details;
        favorite = details.isFavorite;
        played = details.played;

        TextView title = titleText;
        if (title != null) title.setText(details.displayTitle());

        TextView meta = metaText;
        if (meta != null) meta.setText(buildMeta(details));

        TextView ov = overviewText;
        if (ov != null) {
            String text = safe(details.overview).trim();
            if (text.isEmpty()) text = "No overview";
            ov.setText(text);
        }

        EmbyClient c = client;
        if (c != null) {
            String posterId = details.id;
            String backdropId = details.id;
            if (details.isType("Episode") && !safe(details.seriesId).isEmpty()) {
                posterId = details.seriesId;
                backdropId = details.seriesId;
            }
            String posterUrl = c.primaryImageUrl(posterId, 520);
            String backdropUrl = c.backdropImageUrl(backdropId, 1280);
            if (posterView != null) ImageLoader.load(posterView, posterUrl, dpToPx(520));
            if (backdropView != null) ImageLoader.load(backdropView, backdropUrl, dpToPx(1280));
        }

        boolean isSeries = details.isType("Series");
        if (seasonSection != null) seasonSection.setVisibility(isSeries ? View.VISIBLE : View.GONE);
        if (episodeSection != null) episodeSection.setVisibility(isSeries ? View.VISIBLE : View.GONE);

        updateFavoriteBtn();
        updatePlayedBtn();
    }

    private void applySeasons(List<EmbySeason> list) {
        seasons = list != null ? list : Collections.emptyList();
        selectedSeasonPos = -1;
        SeasonChipAdapter a = seasonAdapter;
        if (a != null) a.setData(seasons, selectedSeasonPos);

        if (!seasons.isEmpty()) {
            EmbySeason initial = chooseInitialSeason(seasons);
            if (initial != null) selectSeason(initial);
        }
    }

    @Nullable
    private static EmbySeason chooseInitialSeason(List<EmbySeason> seasons) {
        if (seasons == null || seasons.isEmpty()) return null;
        for (int i = 0; i < seasons.size(); i++) {
            EmbySeason s = seasons.get(i);
            if (s != null && s.seasonNumber > 0) return s;
        }
        return seasons.get(0);
    }

    private void applyEpisodes(List<EmbyEpisode> list, EmbySeason season) {
        episodes = list != null ? new ArrayList<>(list) : Collections.emptyList();
        selectedEpisodePos = -1;

        EpisodeChipAdapter a = episodeAdapter;
        if (a != null) a.setData(episodes, selectedEpisodePos);

        if (!episodes.isEmpty()) {
            selectEpisode(episodes.get(0));
        }
    }

    private void selectSeason(EmbySeason season) {
        if (season == null) return;
        int idx = indexOfSeason(season.id);
        if (idx < 0) return;
        selectedSeasonPos = idx;
        SeasonChipAdapter a = seasonAdapter;
        if (a != null) a.setData(seasons, selectedSeasonPos);
        if (seasonList != null) seasonList.smoothScrollToPosition(idx);
        loadEpisodesForSeason(season);
    }

    private int indexOfSeason(String seasonId) {
        String id = safe(seasonId);
        if (id.isEmpty()) return -1;
        for (int i = 0; i < seasons.size(); i++) {
            EmbySeason s = seasons.get(i);
            if (s != null && id.equals(s.id)) return i;
        }
        return -1;
    }

    private void loadEpisodesForSeason(EmbySeason season) {
        EmbyClient c = client;
        EmbyItemDetails d = itemDetails;
        if (c == null || d == null || season == null) return;

        EpisodeChipAdapter a = episodeAdapter;
        if (a != null) a.setData(Collections.emptyList(), -1);
        episodes = Collections.emptyList();
        selectedEpisodePos = -1;
        updatePlayedBtn();

        new Thread(
                        () -> {
                            try {
                                List<EmbyEpisode> eps = c.listEpisodes(d.id, season.id, 500);
                                runOnUiThread(
                                        () -> {
                                            if (isFinishing() || isDestroyed()) return;
                                            applyEpisodes(eps, season);
                                        });
                            } catch (Exception e) {
                                runOnUiThread(
                                        () ->
                                                Toast.makeText(
                                                                ItemDetailActivity.this,
                                                                "Load episodes failed: "
                                                                        + String.valueOf(e.getMessage()),
                                                                Toast.LENGTH_LONG)
                                                        .show());
                            }
                        },
                        "tv-legacy-episodes")
                .start();
    }

    private void selectEpisode(EmbyEpisode episode) {
        if (episode == null) return;
        int idx = indexOfEpisode(episode.id);
        if (idx < 0) return;
        selectedEpisodePos = idx;
        EpisodeChipAdapter a = episodeAdapter;
        if (a != null) a.setData(episodes, selectedEpisodePos);
        if (episodeList != null) episodeList.smoothScrollToPosition(idx);
        updatePlayedBtn();
    }

    private int indexOfEpisode(String episodeId) {
        String id = safe(episodeId);
        if (id.isEmpty()) return -1;
        for (int i = 0; i < episodes.size(); i++) {
            EmbyEpisode e = episodes.get(i);
            if (e != null && id.equals(e.id)) return i;
        }
        return -1;
    }

    private void play() {
        EmbyClient c = client;
        EmbyItemDetails d = itemDetails;
        if (c == null || d == null) return;

        String targetId = d.id;
        long posMs = Math.max(0L, d.playbackPositionMs);
        String title = d.displayTitle();

        if (d.isType("Series")) {
            EmbyEpisode ep = selectedEpisodePos >= 0 && selectedEpisodePos < episodes.size()
                    ? episodes.get(selectedEpisodePos)
                    : null;
            if (ep == null) {
                Toast.makeText(this, "Select an episode", Toast.LENGTH_SHORT).show();
                return;
            }
            targetId = ep.id;
            posMs = Math.max(0L, ep.playbackPositionMs);
            title = d.name + " " + formatSeasonEpisode(ep.seasonNumber, ep.episodeNumber);
        } else if (d.isType("Movie") || d.isType("Episode")) {
            if (initialPositionMs > 0L && posMs <= 0L) {
                posMs = initialPositionMs;
            }
        }

        String url = c.streamUrl(targetId);
        if (url.isEmpty()) {
            Toast.makeText(this, "Missing media url", Toast.LENGTH_LONG).show();
            return;
        }

        Intent i = new Intent(this, PlayerActivity.class);
        i.putExtra(PlayerActivity.EXTRA_TITLE, title);
        i.putExtra(PlayerActivity.EXTRA_URL, url);
        if (posMs > 0L) {
            i.putExtra(PlayerActivity.EXTRA_POSITION_MS, posMs);
        }
        startActivity(i);
    }

    private void toggleFavorite() {
        EmbyClient c = client;
        EmbyItemDetails d = itemDetails;
        if (c == null || d == null) return;

        boolean newState = !favorite;
        if (favoriteBtn != null) favoriteBtn.setEnabled(false);
        new Thread(
                        () -> {
                            try {
                                boolean ok = c.setFavorite(d.id, newState);
                                runOnUiThread(
                                        () -> {
                                            if (isFinishing() || isDestroyed()) return;
                                            if (favoriteBtn != null) favoriteBtn.setEnabled(true);
                                            if (!ok) return;
                                            favorite = newState;
                                            updateFavoriteBtn();
                                        });
                            } catch (Exception e) {
                                runOnUiThread(
                                        () -> {
                                            if (isFinishing() || isDestroyed()) return;
                                            if (favoriteBtn != null) favoriteBtn.setEnabled(true);
                                            Toast.makeText(
                                                            ItemDetailActivity.this,
                                                            "Favorite failed: " + String.valueOf(e.getMessage()),
                                                            Toast.LENGTH_LONG)
                                                    .show();
                                        });
                            }
                        },
                        "tv-legacy-favorite")
                .start();
    }

    private void togglePlayed() {
        EmbyClient c = client;
        EmbyItemDetails d = itemDetails;
        if (c == null || d == null) return;

        String targetId = d.id;
        boolean current = played;

        boolean newState = !current;
        if (playedBtn != null) playedBtn.setEnabled(false);
        String finalTargetId = targetId;
        boolean finalCurrent = current;
        new Thread(
                        () -> {
                            try {
                                boolean ok = c.setPlayed(finalTargetId, newState);
                                runOnUiThread(
                                        () -> {
                                            if (isFinishing() || isDestroyed()) return;
                                            if (playedBtn != null) playedBtn.setEnabled(true);
                                            if (!ok) return;
                                            played = newState;
                                            if (finalCurrent != newState) updatePlayedBtn();
                                        });
                            } catch (Exception e) {
                                runOnUiThread(
                                        () -> {
                                            if (isFinishing() || isDestroyed()) return;
                                            if (playedBtn != null) playedBtn.setEnabled(true);
                                            Toast.makeText(
                                                            ItemDetailActivity.this,
                                                            "Mark played failed: "
                                                                    + String.valueOf(e.getMessage()),
                                                            Toast.LENGTH_LONG)
                                                    .show();
                                        });
                            }
                        },
                        "tv-legacy-played")
                .start();
    }

    private void handleSeasonInput() {
        String raw = seasonInput != null ? safe(seasonInput.getText() != null ? seasonInput.getText().toString() : "") : "";
        int seasonNumber = parsePositiveInt(raw);
        if (seasonNumber <= 0) {
            Toast.makeText(this, "Invalid season", Toast.LENGTH_SHORT).show();
            return;
        }
        for (int i = 0; i < seasons.size(); i++) {
            EmbySeason s = seasons.get(i);
            if (s != null && s.seasonNumber == seasonNumber) {
                selectSeason(s);
                return;
            }
        }
        Toast.makeText(this, "Season not found", Toast.LENGTH_SHORT).show();
    }

    private void handleEpisodeInput() {
        String raw = episodeInput != null ? safe(episodeInput.getText() != null ? episodeInput.getText().toString() : "") : "";
        int epNumber = parsePositiveInt(raw);
        if (epNumber <= 0) {
            Toast.makeText(this, "Invalid episode", Toast.LENGTH_SHORT).show();
            return;
        }
        for (int i = 0; i < episodes.size(); i++) {
            EmbyEpisode e = episodes.get(i);
            if (e != null && e.episodeNumber == epNumber) {
                selectEpisode(e);
                return;
            }
        }
        Toast.makeText(this, "Episode not found", Toast.LENGTH_SHORT).show();
    }

    private void updateFavoriteBtn() {
        Button b = favoriteBtn;
        if (b == null) return;
        b.setText(favorite ? getString(R.string.unfavorite) : getString(R.string.favorite));
    }

    private void updatePlayedBtn() {
        Button b = playedBtn;
        if (b == null) return;
        b.setText(played ? getString(R.string.mark_unplayed) : getString(R.string.mark_played));
    }

    private static String buildMeta(EmbyItemDetails details) {
        if (details == null) return "";
        String date = safe(details.premiereDate);
        if (details.isType("Series")) {
            return date;
        }

        String dur = formatDuration(details.runtimeTicks);
        if (date.isEmpty()) return dur;
        if (dur.isEmpty()) return date;
        return date + " \u00b7 " + dur;
    }

    private static String formatDuration(long runtimeTicks) {
        long ticks = Math.max(0L, runtimeTicks);
        if (ticks <= 0L) return "";
        long ms = ticks / 10000L;
        long totalMin = ms / 60000L;
        if (totalMin <= 0L) return "";
        long h = totalMin / 60L;
        long m = totalMin % 60L;
        if (h > 0L) {
            if (m > 0L) return String.format(Locale.US, "%dh %dm", h, m);
            return String.format(Locale.US, "%dh", h);
        }
        return String.format(Locale.US, "%dmin", totalMin);
    }

    private static String formatSeasonEpisode(int season, int episode) {
        if (season <= 0 && episode <= 0) return "";
        if (season <= 0) return "E" + episode;
        if (episode <= 0) return "S" + season;
        return String.format(Locale.US, "S%02dE%02d", season, episode);
    }

    private int dpToPx(int dp) {
        float density = getResources().getDisplayMetrics().density;
        return Math.round(dp * density);
    }

    private static int computeSelectorItemWidthPx(RecyclerView rv, int visibleCount) {
        if (rv == null) return 0;
        int count = Math.max(1, visibleCount);
        int w = rv.getWidth() > 0 ? rv.getWidth() : rv.getResources().getDisplayMetrics().widthPixels;
        int padding = rv.getPaddingLeft() + rv.getPaddingRight();
        int spacing = Math.round(rv.getResources().getDisplayMetrics().density * 12f);
        int available = Math.max(0, w - padding - spacing * (count + 1));
        return Math.max(0, available / count);
    }

    private static int parsePositiveInt(String s) {
        String v = safe(s);
        if (v.isEmpty()) return 0;
        try {
            return Math.max(0, Integer.parseInt(v));
        } catch (Exception ignored) {
            return 0;
        }
    }

    private static String safe(String s) {
        return s != null ? s.trim() : "";
    }

    private static final class SeasonChipAdapter extends RecyclerView.Adapter<SeasonChipAdapter.Vh> {
        interface Listener {
            void onSeasonClicked(EmbySeason season);
        }

        private final Listener listener;
        private List<EmbySeason> seasons = Collections.emptyList();
        private int selectedPos = -1;
        private int itemWidthPx = 0;

        SeasonChipAdapter(Listener listener) {
            this.listener = listener;
        }

        void setData(List<EmbySeason> seasons, int selectedPos) {
            this.seasons = seasons != null ? seasons : Collections.emptyList();
            this.selectedPos = selectedPos;
            notifyDataSetChanged();
        }

        void setItemWidthPx(int px) {
            int v = Math.max(0, px);
            if (v == itemWidthPx) return;
            itemWidthPx = v;
            notifyDataSetChanged();
        }

        @NonNull
        @Override
        public Vh onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View v =
                    LayoutInflater.from(parent.getContext()).inflate(R.layout.item_detail_chip, parent, false);
            if (itemWidthPx > 0) {
                RecyclerView.LayoutParams lp = (RecyclerView.LayoutParams) v.getLayoutParams();
                lp.width = itemWidthPx;
                v.setLayoutParams(lp);
            }
            return new Vh(v);
        }

        @Override
        public void onBindViewHolder(@NonNull Vh holder, int position) {
            EmbySeason s = seasons.get(position);
            String text = s != null && s.seasonNumber > 0 ? ("S" + s.seasonNumber) : "S0";
            holder.text.setText(text);
            holder.itemView.setSelected(position == selectedPos);
            holder.itemView.setOnClickListener(v -> listener.onSeasonClicked(s));
        }

        @Override
        public int getItemCount() {
            return seasons != null ? seasons.size() : 0;
        }

        static final class Vh extends RecyclerView.ViewHolder {
            final TextView text;

            Vh(@NonNull View itemView) {
                super(itemView);
                text = itemView.findViewById(R.id.chip_text);
            }
        }
    }

    private static final class EpisodeChipAdapter extends RecyclerView.Adapter<EpisodeChipAdapter.Vh> {
        interface Listener {
            void onEpisodeClicked(EmbyEpisode episode);
        }

        private final Listener listener;
        private List<EmbyEpisode> episodes = Collections.emptyList();
        private int selectedPos = -1;
        private int itemWidthPx = 0;

        EpisodeChipAdapter(Listener listener) {
            this.listener = listener;
        }

        void setData(List<EmbyEpisode> episodes, int selectedPos) {
            this.episodes = episodes != null ? episodes : Collections.emptyList();
            this.selectedPos = selectedPos;
            notifyDataSetChanged();
        }

        void setItemWidthPx(int px) {
            int v = Math.max(0, px);
            if (v == itemWidthPx) return;
            itemWidthPx = v;
            notifyDataSetChanged();
        }

        @NonNull
        @Override
        public Vh onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View v =
                    LayoutInflater.from(parent.getContext()).inflate(R.layout.item_detail_chip, parent, false);
            if (itemWidthPx > 0) {
                RecyclerView.LayoutParams lp = (RecyclerView.LayoutParams) v.getLayoutParams();
                lp.width = itemWidthPx;
                v.setLayoutParams(lp);
            }
            return new Vh(v);
        }

        @Override
        public void onBindViewHolder(@NonNull Vh holder, int position) {
            EmbyEpisode e = episodes.get(position);
            String text = e != null ? String.valueOf(Math.max(0, e.episodeNumber)) : "";
            holder.text.setText(text);
            holder.itemView.setSelected(position == selectedPos);
            holder.itemView.setAlpha(e != null && e.played ? 0.65f : 1.0f);
            holder.itemView.setOnClickListener(v -> listener.onEpisodeClicked(e));
        }

        @Override
        public int getItemCount() {
            return episodes != null ? episodes.size() : 0;
        }

        static final class Vh extends RecyclerView.ViewHolder {
            final TextView text;

            Vh(@NonNull View itemView) {
                super(itemView);
                text = itemView.findViewById(R.id.chip_text);
            }
        }
    }
}
