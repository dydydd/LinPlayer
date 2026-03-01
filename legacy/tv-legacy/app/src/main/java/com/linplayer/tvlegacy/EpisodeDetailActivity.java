package com.linplayer.tvlegacy;

import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import com.linplayer.tvlegacy.backend.Backends;
import com.linplayer.tvlegacy.backend.Callback;

public final class EpisodeDetailActivity extends AppCompatActivity {
    static final String EXTRA_SHOW_ID = "show_id";
    static final String EXTRA_EPISODE_INDEX = "episode_index";

    private String showId = "";
    private int episodeIndex = 1;

    private String showTitle = "Unknown show";
    @Nullable private Show show;
    @Nullable private Episode episode;

    @Nullable private ImageView backdropView;
    @Nullable private ImageView posterView;
    @Nullable private TextView titleText;
    @Nullable private TextView metaText;
    @Nullable private TextView overviewText;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_episode_detail);

        showId = safe(getIntent().getStringExtra(EXTRA_SHOW_ID));
        episodeIndex = getIntent().getIntExtra(EXTRA_EPISODE_INDEX, 1);

        if (showId.isEmpty()) {
            Toast.makeText(this, "Missing show id", Toast.LENGTH_LONG).show();
            finish();
            return;
        }

        backdropView = findViewById(R.id.detail_backdrop);
        posterView = findViewById(R.id.detail_poster);
        titleText = findViewById(R.id.detail_title);
        metaText = findViewById(R.id.detail_meta);
        overviewText = findViewById(R.id.detail_overview);

        TextView title = titleText;
        if (title != null) title.setText("Loading...");
        TextView meta = metaText;
        if (meta != null) meta.setText("EP " + episodeIndex);
        TextView ov = overviewText;
        if (ov != null) ov.setText("");

        View seasonSection = findViewById(R.id.season_section);
        if (seasonSection != null) seasonSection.setVisibility(View.GONE);
        View episodeSection = findViewById(R.id.episode_section);
        if (episodeSection != null) episodeSection.setVisibility(View.GONE);

        Button playBtn = findViewById(R.id.btn_play);
        playBtn.setOnClickListener(v -> openPlayer());

        Backends.media(this)
                .getShow(
                        showId,
                        new Callback<Show>() {
                            @Override
                            public void onSuccess(Show v) {
                                if (isFinishing() || isDestroyed()) return;
                                show = v;
                                showTitle = v != null ? safe(v.title) : "Unknown show";
                                applyUi();
                            }

                            @Override
                            public void onError(Throwable error) {
                                if (isFinishing() || isDestroyed()) return;
                                show = null;
                                showTitle = "Unknown show";
                                applyUi();
                            }
                        });

        Backends.media(this)
                .getEpisode(
                        showId,
                        episodeIndex,
                        new Callback<Episode>() {
                            @Override
                            public void onSuccess(Episode v) {
                                if (isFinishing() || isDestroyed()) return;
                                episode = v;
                                applyUi();
                            }

                            @Override
                            public void onError(Throwable error) {
                                if (isFinishing() || isDestroyed()) return;
                                episode = null;
                                TextView title = titleText;
                                if (title != null) title.setText("Episode " + episodeIndex);
                                TextView ov = overviewText;
                                if (ov != null) {
                                    ov.setText(
                                            "Load episode failed: "
                                                    + String.valueOf(error.getMessage()));
                                }
                            }
                        });
    }

    private void openPlayer() {
        Episode current = episode;
        if (current == null || safe(current.mediaUrl).isEmpty()) {
            Toast.makeText(this, "Missing media url", Toast.LENGTH_LONG).show();
            return;
        }
        Intent i = new Intent(this, PlayerActivity.class);
        i.putExtra(PlayerActivity.EXTRA_URL, safe(current.mediaUrl));
        i.putExtra(PlayerActivity.EXTRA_TITLE, safe(current.title));
        i.putExtra(PlayerActivity.EXTRA_SHOW_ID, showId);
        i.putExtra(PlayerActivity.EXTRA_EPISODE_INDEX, episodeIndex);
        i.putExtra(PlayerActivity.EXTRA_SHOW_TITLE, showTitle);
        i.putExtra(PlayerActivity.EXTRA_SEASON_NUMBER, current.seasonNumber);
        i.putExtra(PlayerActivity.EXTRA_EPISODE_NUMBER, current.episodeNumber);
        startActivity(i);
    }

    private void applyUi() {
        Episode ep = episode;
        Show s = show;

        TextView title = titleText;
        if (title != null) {
            String t = ep != null ? safe(ep.title) : "";
            title.setText(t.isEmpty() ? ("Episode " + episodeIndex) : t);
        }

        TextView meta = metaText;
        if (meta != null) meta.setText(buildEpisodeMeta(showTitle, ep, episodeIndex));

        TextView ov = overviewText;
        if (ov != null) {
            String text = ep != null ? safe(ep.overview) : "";
            if (text.isEmpty()) text = "No overview";
            ov.setText(text);
        }

        String poster = s != null ? safe(s.posterUrl) : "";
        String backdrop = s != null ? safe(s.backdropUrl) : "";
        String thumb = ep != null ? safe(ep.thumbUrl) : "";
        if (poster.isEmpty()) poster = thumb;
        if (backdrop.isEmpty()) backdrop = thumb;

        ImageView posterIv = posterView;
        if (posterIv != null) ImageLoader.load(posterIv, poster, dpToPx(520));
        ImageView backdropIv = backdropView;
        if (backdropIv != null) ImageLoader.load(backdropIv, backdrop, dpToPx(1280));
    }

    private int dpToPx(int dp) {
        float density = getResources().getDisplayMetrics().density;
        return Math.round(dp * density);
    }

    private static String buildEpisodeMeta(String showTitle, Episode episode, int index) {
        String st = showTitle != null ? showTitle.trim() : "";
        StringBuilder sb = new StringBuilder();
        if (!st.isEmpty()) sb.append(st);

        int season = episode != null ? episode.seasonNumber : 0;
        int ep = episode != null ? episode.episodeNumber : 0;
        if (season > 0 && ep > 0) {
            if (sb.length() > 0) sb.append(" · ");
            sb.append("S").append(season).append("E").append(ep);
        } else {
            if (sb.length() > 0) sb.append(" · ");
            sb.append("EP ").append(index);
        }
        return sb.toString();
    }

    private static String safe(String s) {
        return s != null ? s.trim() : "";
    }
}

