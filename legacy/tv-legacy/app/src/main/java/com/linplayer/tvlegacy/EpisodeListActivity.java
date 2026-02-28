package com.linplayer.tvlegacy;

import android.content.Intent;
import android.os.Bundle;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.linplayer.tvlegacy.backend.Backends;
import com.linplayer.tvlegacy.backend.Callback;
import java.util.Collections;
import java.util.List;

public final class EpisodeListActivity extends AppCompatActivity {
    static final String EXTRA_SHOW_ID = "show_id";

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_episode_list);

        String showId = getIntent().getStringExtra(EXTRA_SHOW_ID);
        if (showId == null || showId.trim().isEmpty()) {
            Toast.makeText(this, "Missing show id", Toast.LENGTH_LONG).show();
            finish();
            return;
        }

        TextView title = findViewById(R.id.episode_list_title);
        title.setText("Loading...");

        Button backBtn = findViewById(R.id.btn_back);
        backBtn.setOnClickListener(v -> finish());

        RecyclerView list = findViewById(R.id.episode_list);
        list.setLayoutManager(new LinearLayoutManager(this));

        Backends.media(this)
                .getShow(
                        showId,
                        new Callback<Show>() {
                            @Override
                            public void onSuccess(Show show) {
                                if (isFinishing() || isDestroyed()) return;
                                String showTitle = show != null ? show.title : "Unknown show";
                                title.setText(
                                        showTitle
                                                + " · "
                                                + getString(R.string.episode_list_title));
                            }

                            @Override
                            public void onError(Throwable error) {
                                if (isFinishing() || isDestroyed()) return;
                                title.setText(getString(R.string.episode_list_title));
                            }
                        });

        Backends.media(this)
                .listEpisodes(
                        showId,
                        new Callback<List<Episode>>() {
                            @Override
                            public void onSuccess(List<Episode> episodes) {
                                if (isFinishing() || isDestroyed()) return;
                                List<Episode> safe =
                                        episodes != null ? episodes : Collections.emptyList();
                                list.setAdapter(
                                        new EpisodeAdapter(
                                                safe,
                                                episode -> {
                                                    Intent i =
                                                            new Intent(
                                                                    EpisodeListActivity.this,
                                                                    EpisodeDetailActivity.class);
                                                    i.putExtra(
                                                            EpisodeDetailActivity.EXTRA_SHOW_ID,
                                                            showId);
                                                    i.putExtra(
                                                            EpisodeDetailActivity
                                                                    .EXTRA_EPISODE_INDEX,
                                                            episode.index);
                                                    startActivity(i);
                                                }));
                            }

                            @Override
                            public void onError(Throwable error) {
                                if (isFinishing() || isDestroyed()) return;
                                Toast.makeText(
                                                EpisodeListActivity.this,
                                                "Load episodes failed: "
                                                        + String.valueOf(error.getMessage()),
                                                Toast.LENGTH_LONG)
                                        .show();
                                list.setAdapter(
                                        new EpisodeAdapter(
                                                Collections.emptyList(), episode -> {}));
                            }
                        });
    }
}
