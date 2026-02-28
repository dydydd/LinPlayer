package com.linplayer.tvlegacy;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import java.util.List;

final class EpisodeAdapter extends RecyclerView.Adapter<EpisodeAdapter.Vh> {
    interface Listener {
        void onEpisodeClicked(Episode episode);
    }

    private final List<Episode> episodes;
    private final Listener listener;

    EpisodeAdapter(List<Episode> episodes, Listener listener) {
        this.episodes = episodes;
        this.listener = listener;
    }

    @NonNull
    @Override
    public Vh onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View v =
                LayoutInflater.from(parent.getContext())
                        .inflate(R.layout.item_episode, parent, false);
        return new Vh(v);
    }

    @Override
    public void onBindViewHolder(@NonNull Vh holder, int position) {
        Episode episode = episodes.get(position);
        holder.index.setText(String.valueOf(episode.index));
        holder.title.setText(episode.title);
        holder.itemView.setOnClickListener(v -> listener.onEpisodeClicked(episode));
    }

    @Override
    public int getItemCount() {
        return episodes != null ? episodes.size() : 0;
    }

    static final class Vh extends RecyclerView.ViewHolder {
        final TextView index;
        final TextView title;

        Vh(@NonNull View itemView) {
            super(itemView);
            index = itemView.findViewById(R.id.episode_index);
            title = itemView.findViewById(R.id.episode_title);
        }
    }
}

