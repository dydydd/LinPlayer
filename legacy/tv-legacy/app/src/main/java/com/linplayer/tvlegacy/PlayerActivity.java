package com.linplayer.tvlegacy;

import android.net.TrafficStats;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.KeyEvent;
import android.view.LayoutInflater;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.view.animation.AlphaAnimation;
import android.view.animation.DecelerateInterpolator;
import android.view.animation.Interpolator;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.Toast;
import android.widget.ViewAnimator;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.linplayer.tvlegacy.backend.Backends;
import com.linplayer.tvlegacy.backend.Callback;
import com.linplayer.tvlegacy.player.PlayerCore;
import com.linplayer.tvlegacy.player.PlayerCoreType;
import com.linplayer.tvlegacy.player.PlayerCores;
import com.linplayer.tvlegacy.player.PlayerTrack;
import com.linplayer.tvlegacy.remote.PlaybackSession;
import com.linplayer.tvlegacy.servers.ServerConfig;
import com.linplayer.tvlegacy.servers.ServerStore;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import okhttp3.Credentials;

public final class PlayerActivity extends AppCompatActivity {
    static final String EXTRA_URL = "url";
    static final String EXTRA_TITLE = "title";
    static final String EXTRA_POSITION_MS = "position_ms";

    static final String EXTRA_SHOW_ID = "show_id";
    static final String EXTRA_EPISODE_INDEX = "episode_index";
    static final String EXTRA_SHOW_TITLE = "show_title";
    static final String EXTRA_SEASON_NUMBER = "season_number";
    static final String EXTRA_EPISODE_NUMBER = "episode_number";

    private static final int PANEL_COUNT = 5;
    private static final int SEEK_MAX = 1000;

    private final Handler main = new Handler(Looper.getMainLooper());
    private final SimpleDateFormat clockFormat = new SimpleDateFormat("HH:mm", Locale.getDefault());

    @Nullable private ViewGroup playerContainer;
    @Nullable private TextView titleText;
    @Nullable private TextView netSpeedText;
    @Nullable private TextView timeText;

    @Nullable private ViewAnimator bottomAnimator;
    private int bottomPanelIndex = 0;

    @Nullable private TextView positionText;
    @Nullable private TextView durationText;
    @Nullable private SeekBar seekBar;

    @Nullable private RecyclerView episodesList;
    @Nullable private RecyclerView subtitlesList;
    @Nullable private RecyclerView audioList;
    @Nullable private RecyclerView coreList;

    @Nullable private PlayerCore playerCore;
    @NonNull private PlayerCoreType coreType = PlayerCoreType.IJK;

    private String url = "";
    private String title = "";
    private long startPositionMs = 0L;

    private String showId = "";
    private String showTitle = "";
    private int episodeIndex = 0;
    private int seasonNumber = 0;
    private int episodeNumber = 0;

    private long lastRxBytes = -1L;
    private long lastRxTimeMs = -1L;

    private boolean userSeeking = false;
    @Nullable private Runnable seekCommitRunnable;
    @Nullable private Runnable tickerRunnable;

    private final List<Episode> episodes = new ArrayList<>();
    private int selectedEpisodePos = -1;

    private boolean subtitlesOff = false;
    @Nullable private Integer selectedSubtitleId;
    @Nullable private Integer selectedAudioId;

    private final List<PlayerTrack> subtitleTracks = new ArrayList<>();
    private final List<PlayerTrack> audioTracks = new ArrayList<>();

    @Nullable private ChipAdapter episodesAdapter;
    @Nullable private ChipAdapter subtitlesAdapter;
    @Nullable private ChipAdapter audioAdapter;
    @Nullable private ChipAdapter coreAdapter;

    private final PlayerCore.Listener coreListener =
            new PlayerCore.Listener() {
                @Override
                public void onTracksChanged() {
                    refreshTracksFromCore();
                    rebuildTrackPanels();
                }

                @Override
                public void onFatalError(@NonNull String message) {
                    if (isFinishing() || isDestroyed()) return;
                    Toast.makeText(PlayerActivity.this, safe(message), Toast.LENGTH_LONG).show();
                }
            };

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_player);

        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        url = safe(getIntent().getStringExtra(EXTRA_URL));
        title = safe(getIntent().getStringExtra(EXTRA_TITLE));
        startPositionMs = Math.max(0L, getIntent().getLongExtra(EXTRA_POSITION_MS, 0L));
        showId = safe(getIntent().getStringExtra(EXTRA_SHOW_ID));
        showTitle = safe(getIntent().getStringExtra(EXTRA_SHOW_TITLE));
        episodeIndex = Math.max(0, getIntent().getIntExtra(EXTRA_EPISODE_INDEX, 0));
        seasonNumber = Math.max(0, getIntent().getIntExtra(EXTRA_SEASON_NUMBER, 0));
        episodeNumber = Math.max(0, getIntent().getIntExtra(EXTRA_EPISODE_NUMBER, 0));

        if (url.isEmpty()) {
            Toast.makeText(this, "Missing media url", Toast.LENGTH_LONG).show();
            finish();
            return;
        }

        playerContainer = findViewById(R.id.player_container);
        titleText = findViewById(R.id.player_title);
        netSpeedText = findViewById(R.id.player_net_speed);
        timeText = findViewById(R.id.player_time);

        bottomAnimator = findViewById(R.id.bottom_panel_animator);
        setupBottomAnimator();

        positionText = findViewById(R.id.player_position);
        durationText = findViewById(R.id.player_duration);
        seekBar = findViewById(R.id.player_seek);
        setupSeekBar();

        episodesList = findViewById(R.id.panel_episodes);
        subtitlesList = findViewById(R.id.panel_subtitles);
        audioList = findViewById(R.id.panel_audio);
        coreList = findViewById(R.id.panel_core);
        setupChipLists();

        refreshTitle();
        initPlayer();
        loadEpisodesIfNeeded();
        startTicker();

        SeekBar sb = seekBar;
        if (sb != null) sb.requestFocus();
    }

    @Override
    protected void onStop() {
        super.onStop();
        stopTicker();
        stopSeekCommit();
        releasePlayerCore(false);
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            if (bottomPanelIndex != 0) {
                setBottomPanel(0);
                return true;
            }
            return super.onKeyDown(keyCode, event);
        }
        if (keyCode == KeyEvent.KEYCODE_DPAD_DOWN) {
            cycleBottomPanel(true);
            return true;
        }
        if (keyCode == KeyEvent.KEYCODE_DPAD_UP) {
            cycleBottomPanel(false);
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    private void setupBottomAnimator() {
        ViewAnimator a = bottomAnimator;
        if (a == null) return;
        Interpolator interpolator = new DecelerateInterpolator();

        AlphaAnimation in = new AlphaAnimation(0f, 1f);
        in.setDuration(120);
        in.setInterpolator(interpolator);

        AlphaAnimation out = new AlphaAnimation(1f, 0f);
        out.setDuration(120);
        out.setInterpolator(interpolator);

        a.setInAnimation(in);
        a.setOutAnimation(out);
    }

    private void setupSeekBar() {
        SeekBar sb = seekBar;
        if (sb == null) return;
        sb.setMax(SEEK_MAX);
        sb.setSplitTrack(false);
        sb.setOnSeekBarChangeListener(
                new SeekBar.OnSeekBarChangeListener() {
                    @Override
                     public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                         if (!fromUser) return;
                        PlayerCore p = playerCore;
                        if (p == null) return;
                        long dur = Math.max(0L, p.getDurationMs());
                        if (dur <= 0L) return;

                        long next = (dur * clamp(progress, 0, SEEK_MAX)) / SEEK_MAX;
                        TextView pt = positionText;
                        if (pt != null) pt.setText(formatTimeMs(next));
                        scheduleSeekCommit();
                    }

                    @Override
                    public void onStartTrackingTouch(SeekBar seekBar) {
                        userSeeking = true;
                        stopSeekCommit();
                    }

                    @Override
                    public void onStopTrackingTouch(SeekBar seekBar) {
                        userSeeking = false;
                        commitSeekNow();
                    }
                });
    }

    private void setupChipLists() {
        final int spacingPx = dpToPx(10);

        episodesAdapter = new ChipAdapter(this::onEpisodeChipClicked);
        subtitlesAdapter = new ChipAdapter(this::onSubtitleChipClicked);
        audioAdapter = new ChipAdapter(this::onAudioChipClicked);
        coreAdapter = new ChipAdapter(this::onCoreChipClicked);

        if (episodesAdapter != null) {
            setupChipRecycler(episodesList, episodesAdapter, spacingPx);
            episodesAdapter.setData(Collections.singletonList(new ChipItem("No episodes", false, false)));
        }
        if (subtitlesAdapter != null) {
            setupChipRecycler(subtitlesList, subtitlesAdapter, spacingPx);
            subtitlesAdapter.setData(Collections.singletonList(new ChipItem("No subtitles", false, false)));
        }
        if (audioAdapter != null) {
            setupChipRecycler(audioList, audioAdapter, spacingPx);
            audioAdapter.setData(Collections.singletonList(new ChipItem("No audio tracks", false, false)));
        }
        if (coreAdapter != null) {
            setupChipRecycler(coreList, coreAdapter, spacingPx);
            rebuildCorePanel();
        }
    }

    private void refreshTitle() {
        String display = buildHudTitle(showTitle, title, seasonNumber, episodeNumber);
        TextView tv = titleText;
        if (tv != null) tv.setText(display);

        PlayerCore p = playerCore;
        if (p != null) PlaybackSession.attach(p, display);
    }

    private void initPlayer() {
        if (AppPrefs.isProxyEnabled(this)) {
            ProxyService.start(this);
        }
        coreType = PlayerCoreType.fromId(AppPrefs.getPlayerCore(this), PlayerCoreType.IJK);
        switchCore(coreType, startPositionMs, true);
    }

    private void loadEpisodesIfNeeded() {
        if (showId.isEmpty()) {
            episodes.clear();
            selectedEpisodePos = -1;
            rebuildEpisodePanel();
            return;
        }

        Backends.media(this)
                .listEpisodes(
                        showId,
                        new Callback<List<Episode>>() {
                            @Override
                            public void onSuccess(List<Episode> list) {
                                if (isFinishing() || isDestroyed()) return;
                                episodes.clear();
                                if (list != null) episodes.addAll(list);
                                selectedEpisodePos = findSelectedEpisodePos(episodes);

                                if (selectedEpisodePos >= 0 && selectedEpisodePos < episodes.size()) {
                                    Episode ep = episodes.get(selectedEpisodePos);
                                    if (ep != null) {
                                        if (seasonNumber <= 0) seasonNumber = Math.max(0, ep.seasonNumber);
                                        if (episodeNumber <= 0) episodeNumber = Math.max(0, ep.episodeNumber);
                                        if (episodeIndex <= 0) episodeIndex = Math.max(0, ep.index);
                                        if (title.isEmpty()) title = safe(ep.title);
                                        refreshTitle();
                                    }
                                }

                                rebuildEpisodePanel();
                            }

                            @Override
                            public void onError(Throwable error) {
                                if (isFinishing() || isDestroyed()) return;
                                episodes.clear();
                                selectedEpisodePos = -1;
                                rebuildEpisodePanel();
                            }
                        });
    }

    private void startTicker() {
        if (tickerRunnable != null) return;
        tickerRunnable =
                new Runnable() {
                    @Override
                    public void run() {
                        if (isFinishing() || isDestroyed()) return;
                        updateClockAndSpeed();
                        updateProgressUi();
                        main.postDelayed(this, 1000L);
                    }
                };
        main.post(tickerRunnable);
    }

    private void stopTicker() {
        Runnable r = tickerRunnable;
        tickerRunnable = null;
        if (r != null) main.removeCallbacks(r);
    }

    private void stopSeekCommit() {
        Runnable r = seekCommitRunnable;
        seekCommitRunnable = null;
        if (r != null) main.removeCallbacks(r);
    }

    private void cycleBottomPanel(boolean forward) {
        int next;
        if (forward) {
            next = (bottomPanelIndex + 1) % PANEL_COUNT;
        } else {
            next = bottomPanelIndex - 1;
            if (next < 0) next = PANEL_COUNT - 1;
        }
        setBottomPanel(next);
    }

    private void setBottomPanel(int index) {
        int next = index;
        if (next < 0) next = 0;
        if (next >= PANEL_COUNT) next = PANEL_COUNT - 1;
        if (next == bottomPanelIndex) return;
        bottomPanelIndex = next;

        ViewAnimator a = bottomAnimator;
        if (a != null) a.setDisplayedChild(next);

        if (next == 0) {
            SeekBar sb = seekBar;
            if (sb != null) sb.requestFocus();
            return;
        }
        if (next == 1) {
            focusRecyclerItem(episodesList, selectedEpisodePos >= 0 ? selectedEpisodePos : 0);
            return;
        }
        if (next == 2) {
            focusRecyclerItem(subtitlesList, 0);
            return;
        }
        if (next == 3) {
            focusRecyclerItem(audioList, 0);
            return;
        }
        if (next == 4) {
            focusRecyclerItem(coreList, 0);
        }
    }

    private void onEpisodeChipClicked(int position) {
        if (episodes.isEmpty()) return;
        if (position < 0 || position >= episodes.size()) return;
        playEpisodeAt(position);
    }

    private void playEpisodeAt(int position) {
        if (position < 0 || position >= episodes.size()) return;
        Episode ep = episodes.get(position);
        if (ep == null) return;

        String playUrl = safe(ep.mediaUrl);
        if (playUrl.isEmpty()) {
            Toast.makeText(this, "Missing media url", Toast.LENGTH_LONG).show();
            return;
        }

        selectedEpisodePos = position;
        episodeIndex = Math.max(0, ep.index);
        seasonNumber = Math.max(0, ep.seasonNumber);
        episodeNumber = Math.max(0, ep.episodeNumber);
        title = safe(ep.title);
        url = playUrl;
        startPositionMs = 0L;

        refreshTitle();
        rebuildEpisodePanel();
        openInCore(0L, true);
    }

    private void rebuildEpisodePanel() {
        ChipAdapter a = episodesAdapter;
        if (a == null) return;

        List<ChipItem> items = new ArrayList<>();
        if (episodes.isEmpty()) {
            items.add(new ChipItem("No episodes", false, false));
        } else {
            for (int i = 0; i < episodes.size(); i++) {
                Episode ep = episodes.get(i);
                items.add(new ChipItem(formatEpisodeLabel(ep), true, i == selectedEpisodePos));
            }
        }
        a.setData(items);
    }

    private int findSelectedEpisodePos(List<Episode> list) {
        if (list == null || list.isEmpty()) return -1;

        if (episodeIndex > 0) {
            for (int i = 0; i < list.size(); i++) {
                Episode ep = list.get(i);
                if (ep != null && ep.index == episodeIndex) return i;
            }
        }
        if (seasonNumber > 0 && episodeNumber > 0) {
            for (int i = 0; i < list.size(); i++) {
                Episode ep = list.get(i);
                if (ep == null) continue;
                if (ep.seasonNumber == seasonNumber && ep.episodeNumber == episodeNumber) return i;
            }
        }
        return 0;
    }

    private static String formatEpisodeLabel(@Nullable Episode ep) {
        if (ep == null) return "EP";
        int s = Math.max(0, ep.seasonNumber);
        int e = Math.max(0, ep.episodeNumber);
        if (s > 0 && e > 0) return String.format(Locale.US, "S%dE%d", s, e);
        int idx = Math.max(1, ep.index);
        return "EP " + idx;
    }

    private static void setupChipRecycler(
            @Nullable RecyclerView rv, @NonNull ChipAdapter adapter, int spacingPx) {
        if (rv == null) return;
        rv.setLayoutManager(
                new LinearLayoutManager(rv.getContext(), LinearLayoutManager.HORIZONTAL, false));
        rv.setAdapter(adapter);
        rv.setItemAnimator(null);
        rv.addItemDecoration(new HorizontalSpacingItemDecoration(spacingPx, true));
    }

    private static void focusRecyclerItem(@Nullable RecyclerView rv, int position) {
        if (rv == null) return;
        final int pos = Math.max(0, position);
        rv.post(
                () -> {
                    RecyclerView.ViewHolder vh = rv.findViewHolderForAdapterPosition(pos);
                    if (vh != null) {
                        vh.itemView.requestFocus();
                        return;
                    }
                    rv.scrollToPosition(pos);
                    rv.post(
                            () -> {
                                RecyclerView.ViewHolder vh2 = rv.findViewHolderForAdapterPosition(pos);
                                if (vh2 != null) vh2.itemView.requestFocus();
                            });
                });
    }

    private void onCoreChipClicked(int position) {
        PlayerCoreType[] types = PlayerCoreType.values();
        if (position < 0 || position >= types.length) return;
        PlayerCoreType next = types[position];
        if (next == coreType) return;

        long pos = 0L;
        PlayerCore p = playerCore;
        if (p != null) pos = Math.max(0L, p.getPositionMs());
        startPositionMs = pos;

        switchCore(next, pos, true);
        Toast.makeText(this, "Switched to " + next.displayName, Toast.LENGTH_SHORT).show();
    }

    private void rebuildCorePanel() {
        ChipAdapter a = coreAdapter;
        if (a == null) return;

        List<ChipItem> items = new ArrayList<>();
        for (PlayerCoreType t : PlayerCoreType.values()) {
            items.add(new ChipItem(t.displayName, true, t == coreType));
        }
        a.setData(items);
    }

    private void switchCore(@NonNull PlayerCoreType nextType, long startPosMs, boolean playWhenReady) {
        ViewGroup container = playerContainer;
        if (container == null) return;

        PlayerCore current = playerCore;
        if (current != null && current.getType() == nextType) {
            openInCore(startPosMs, playWhenReady);
            return;
        }

        // Important: fully release native player(s) first, then GC, otherwise OOM is likely on API 19.
        releasePlayerCore(true);

        coreType = nextType;
        AppPrefs.setPlayerCore(this, nextType.id);
        rebuildCorePanel();

        PlayerCore p = PlayerCores.create(this, nextType);
        p.setListener(coreListener);
        playerCore = p;

        container.removeAllViews();
        container.addView(
                p.getView(),
                new ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        openInCore(startPosMs, playWhenReady);
        refreshTitle();
        refreshTracksFromCore();
        rebuildTrackPanels();
    }

    private void openInCore(long startPosMs, boolean playWhenReady) {
        PlayerCore p = playerCore;
        if (p == null) return;
        Map<String, String> playbackHeaders = buildPlaybackHeaders(url);
        p.open(url, playbackHeaders, startPosMs, playWhenReady);
        applyTrackSelection();
    }

    private void releasePlayerCore(boolean forceGc) {
        PlayerCore p = playerCore;
        playerCore = null;
        boolean hadCore = p != null;
        if (p != null) {
            try {
                p.setListener(null);
            } catch (Exception ignored) {
            }
            PlaybackSession.detach(p);
            try {
                p.release();
            } catch (Exception ignored) {
            }
        }

        ViewGroup container = playerContainer;
        if (container != null) {
            try {
                container.removeAllViews();
            } catch (Exception ignored) {
            }
        }

        if (forceGc && hadCore) forceReleaseGc();
    }

    private static void forceReleaseGc() {
        try {
            System.gc();
            System.runFinalization();
            System.gc();
        } catch (Throwable ignored) {
        }
    }

    private void onSubtitleChipClicked(int position) {
        if (position == 0) {
            subtitlesOff = true;
        } else if (position == 1) {
            subtitlesOff = false;
            selectedSubtitleId = null;
        } else {
            int idx = position - 2;
            if (idx < 0 || idx >= subtitleTracks.size()) return;
            PlayerTrack t = subtitleTracks.get(idx);
            subtitlesOff = false;
            selectedSubtitleId = t.id;
        }
        applyTrackSelection();
        rebuildTrackPanels();
    }

    private void onAudioChipClicked(int position) {
        if (position == 0) {
            selectedAudioId = null;
        } else {
            int idx = position - 1;
            if (idx < 0 || idx >= audioTracks.size()) return;
            PlayerTrack t = audioTracks.get(idx);
            selectedAudioId = t.id;
        }
        applyTrackSelection();
        rebuildTrackPanels();
    }

    private void refreshTracksFromCore() {
        subtitleTracks.clear();
        audioTracks.clear();

        PlayerCore p = playerCore;
        if (p != null) {
            try {
                subtitleTracks.addAll(p.getSubtitleTracks());
            } catch (Exception ignored) {
            }
            try {
                audioTracks.addAll(p.getAudioTracks());
            } catch (Exception ignored) {
            }
        }

        if (selectedSubtitleId != null && !containsTrackId(subtitleTracks, selectedSubtitleId)) {
            selectedSubtitleId = null;
        }
        if (selectedAudioId != null && !containsTrackId(audioTracks, selectedAudioId)) {
            selectedAudioId = null;
        }
    }

    private void rebuildTrackPanels() {
        buildSubtitlePanel();
        buildAudioPanel();
    }

    private void buildSubtitlePanel() {
        ChipAdapter a = subtitlesAdapter;
        if (a == null) return;

        List<ChipItem> items = new ArrayList<>();
        if (subtitleTracks.isEmpty()) {
            if (coreType == PlayerCoreType.IJK) {
                items.add(new ChipItem("IjkPlayer: use libVLC for subtitles", false, false));
            } else {
                items.add(new ChipItem("No subtitles", false, false));
            }
        } else {
            items.add(new ChipItem("Off", true, subtitlesOff));
            items.add(new ChipItem("Auto", true, !subtitlesOff && selectedSubtitleId == null));
            for (PlayerTrack t : subtitleTracks) {
                boolean selected = !subtitlesOff && selectedSubtitleId != null && t.id == selectedSubtitleId;
                items.add(new ChipItem(t.label, true, selected));
            }
        }
        a.setData(items);
    }

    private void buildAudioPanel() {
        ChipAdapter a = audioAdapter;
        if (a == null) return;

        List<ChipItem> items = new ArrayList<>();
        if (audioTracks.isEmpty()) {
            if (coreType == PlayerCoreType.IJK) {
                items.add(new ChipItem("IjkPlayer: use libVLC for tracks", false, false));
            } else {
                items.add(new ChipItem("No audio tracks", false, false));
            }
        } else {
            items.add(new ChipItem("Auto", true, selectedAudioId == null));
            for (PlayerTrack t : audioTracks) {
                boolean selected = selectedAudioId != null && t.id == selectedAudioId;
                items.add(new ChipItem(t.label, true, selected));
            }
        }
        a.setData(items);
    }

    private static boolean containsTrackId(@NonNull List<PlayerTrack> list, @NonNull Integer id) {
        if (list.isEmpty()) return false;
        for (PlayerTrack t : list) {
            if (t.id == id) return true;
        }
        return false;
    }

    private void applyTrackSelection() {
        PlayerCore p = playerCore;
        if (p == null) return;

        try {
            p.selectAudioTrack(selectedAudioId);
        } catch (Exception ignored) {
        }

        try {
            p.setSubtitlesEnabled(!subtitlesOff);
            p.selectSubtitleTrack(!subtitlesOff ? selectedSubtitleId : null);
        } catch (Exception ignored) {
        }
    }

    private void scheduleSeekCommit() {
        stopSeekCommit();
        seekCommitRunnable =
                new Runnable() {
                    @Override
                    public void run() {
                        seekCommitRunnable = null;
                        commitSeekNow();
                    }
                };
        main.postDelayed(seekCommitRunnable, 350L);
    }

    private void commitSeekNow() {
        PlayerCore p = playerCore;
        SeekBar sb = seekBar;
        if (p == null || sb == null) return;

        long dur = Math.max(0L, p.getDurationMs());
        if (dur <= 0L) return;

        int progress = clamp(sb.getProgress(), 0, SEEK_MAX);
        long next = (dur * progress) / SEEK_MAX;
        p.seekTo(next);
    }

    private void updateClockAndSpeed() {
        TextView t = timeText;
        if (t != null) {
            t.setText(clockFormat.format(new Date()));
        }

        TextView speed = netSpeedText;
        if (speed == null) return;

        long rx = TrafficStats.getTotalRxBytes();
        long nowMs = SystemClock.elapsedRealtime();
        if (rx <= 0L) {
            speed.setText("--");
            lastRxBytes = -1L;
            lastRxTimeMs = -1L;
            return;
        }
        if (lastRxBytes < 0L || lastRxTimeMs < 0L) {
            lastRxBytes = rx;
            lastRxTimeMs = nowMs;
            speed.setText("--");
            return;
        }

        long deltaBytes = Math.max(0L, rx - lastRxBytes);
        long deltaMs = Math.max(1L, nowMs - lastRxTimeMs);
        double bytesPerSecond = (deltaBytes * 1000.0) / deltaMs;
        speed.setText(formatSpeed(bytesPerSecond));
        lastRxBytes = rx;
        lastRxTimeMs = nowMs;
    }

    private void updateProgressUi() {
        PlayerCore p = playerCore;
        if (p == null) return;

        long dur = Math.max(0L, p.getDurationMs());

        long pos = Math.max(0L, p.getPositionMs());
        long buf = Math.max(0L, p.getBufferedPositionMs());

        TextView dt = durationText;
        if (dt != null) dt.setText(formatTimeMs(dur));

        SeekBar sb = seekBar;
        if (sb == null) return;

        if (dur <= 0L) {
            if (!userSeeking) {
                sb.setProgress(0);
                sb.setSecondaryProgress(0);
                TextView pt = positionText;
                if (pt != null) pt.setText("00:00");
            }
            return;
        }

        if (!userSeeking) {
            int progress = (int) clampLong((pos * SEEK_MAX) / dur, 0, SEEK_MAX);
            int secondary = (int) clampLong((buf * SEEK_MAX) / dur, 0, SEEK_MAX);
            sb.setProgress(progress);
            sb.setSecondaryProgress(secondary);
            TextView pt = positionText;
            if (pt != null) pt.setText(formatTimeMs(pos));
        }
    }

    @Nullable
    private Map<String, String> buildPlaybackHeaders(String playUrl) {
        String play = safe(playUrl);
        if (play.isEmpty()) return null;

        ServerConfig active = ServerStore.getActive(this);
        if (active == null || !active.isType("webdav")) return null;

        String base = normalizeBaseUrl(active.baseUrl);
        if (!base.isEmpty() && play.startsWith(base)) {
            String auth = Credentials.basic(active.username, active.password);
            Map<String, String> headers = new HashMap<>(1);
            headers.put("Authorization", auth);
            return headers;
        }
        return null;
    }

    private static String normalizeBaseUrl(String baseUrl) {
        String v = baseUrl != null ? baseUrl.trim() : "";
        while (v.endsWith("/")) v = v.substring(0, v.length() - 1);
        return v;
    }

    private int dpToPx(int dp) {
        float density = getResources().getDisplayMetrics().density;
        return Math.round(dp * density);
    }

    private static int clamp(int v, int min, int max) {
        return v < min ? min : (v > max ? max : v);
    }

    private static long clampLong(long v, long min, long max) {
        return v < min ? min : (v > max ? max : v);
    }

    private static String buildHudTitle(String showTitle, String title, int season, int episode) {
        String t = safe(title);
        String st = safe(showTitle);
        if (t.isEmpty() && !st.isEmpty()) t = st;
        if (season > 0 && episode > 0) return "第" + season + "季 第" + episode + "集 " + t;
        if (episode > 0) return "第" + episode + "集 " + t;
        return !t.isEmpty() ? t : "Player";
    }

    private static String formatSpeed(double bytesPerSecond) {
        if (bytesPerSecond <= 0) return "--";
        double kb = bytesPerSecond / 1024.0;
        if (kb >= 1024.0) return String.format(Locale.US, "%.1f MB/s", kb / 1024.0);
        if (kb >= 100.0) return String.format(Locale.US, "%.0f KB/s", kb);
        return String.format(Locale.US, "%.1f KB/s", kb);
    }

    private static String formatTimeMs(long ms) {
        long total = Math.max(0L, ms / 1000L);
        long s = total % 60L;
        long m = (total / 60L) % 60L;
        long h = total / 3600L;
        if (h > 0L) return String.format(Locale.US, "%d:%02d:%02d", h, m, s);
        return String.format(Locale.US, "%02d:%02d", m, s);
    }

    private static final class ChipItem {
        final String text;
        final boolean enabled;
        final boolean selected;

        ChipItem(String text, boolean enabled, boolean selected) {
            this.text = text != null ? text : "";
            this.enabled = enabled;
            this.selected = selected;
        }
    }

    private static final class ChipAdapter extends RecyclerView.Adapter<ChipAdapter.Vh> {
        interface Listener {
            void onChipClicked(int position);
        }

        private final List<ChipItem> items = new ArrayList<>();
        private final Listener listener;

        ChipAdapter(Listener listener) {
            this.listener = listener;
        }

        void setData(List<ChipItem> list) {
            items.clear();
            if (list != null) items.addAll(list);
            notifyDataSetChanged();
        }

        @NonNull
        @Override
        public Vh onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            TextView v =
                    (TextView)
                            LayoutInflater.from(parent.getContext())
                                    .inflate(R.layout.item_detail_chip, parent, false);
            return new Vh(v);
        }

        @Override
        public void onBindViewHolder(@NonNull Vh holder, int position) {
            ChipItem item = items.get(position);
            holder.text.setText(item.text);
            holder.text.setEnabled(item.enabled);
            holder.text.setSelected(item.selected);
            holder.text.setAlpha(item.enabled ? 1f : 0.55f);
            holder.text.setOnClickListener(
                    v -> {
                        int pos = holder.getAdapterPosition();
                        if (pos == RecyclerView.NO_POSITION) return;
                        listener.onChipClicked(pos);
                    });
        }

        @Override
        public int getItemCount() {
            return items.size();
        }

        static final class Vh extends RecyclerView.ViewHolder {
            final TextView text;

            Vh(@NonNull TextView itemView) {
                super(itemView);
                text = itemView;
            }
        }
    }

    private static String safe(String s) {
        return s != null ? s.trim() : "";
    }
}
