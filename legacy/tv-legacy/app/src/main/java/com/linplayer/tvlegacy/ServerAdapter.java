package com.linplayer.tvlegacy;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import com.linplayer.tvlegacy.servers.ServerConfig;
import java.util.ArrayList;
import java.util.List;

final class ServerAdapter extends RecyclerView.Adapter<ServerAdapter.Vh> {
    interface Listener {
        void onServerClicked(ServerConfig server);

        void onServerLongClicked(ServerConfig server);
    }

    private final List<ServerConfig> servers = new ArrayList<>();
    private final Listener listener;
    private String activeId = "";

    ServerAdapter(Listener listener) {
        this.listener = listener;
    }

    void setData(List<ServerConfig> list, String activeId) {
        this.activeId = activeId != null ? activeId : "";
        servers.clear();
        if (list != null) servers.addAll(list);
        notifyDataSetChanged();
    }

    @NonNull
    @Override
    public Vh onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View v = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_server_bar, parent, false);
        return new Vh(v);
    }

    @Override
    public void onBindViewHolder(@NonNull Vh holder, int position) {
        ServerConfig c = servers.get(position);
        boolean active = c != null && c.id != null && c.id.equals(activeId);
        String name = c != null ? c.effectiveName() : "Server";
        holder.name.setText((active ? "✓ " : "") + name);

        String remark = c != null ? safe(c.remark) : "";
        if (remark.isEmpty()) {
            holder.remark.setVisibility(View.GONE);
        } else {
            holder.remark.setVisibility(View.VISIBLE);
            holder.remark.setText(remark);
        }

        String iconUrl = c != null ? safe(c.iconUrl) : "";
        if (!iconUrl.isEmpty()) {
            holder.avatarText.setVisibility(View.GONE);
            holder.avatarImg.setVisibility(View.VISIBLE);
            ImageLoader.load(holder.avatarImg, iconUrl, 96);
        } else {
            holder.avatarImg.setVisibility(View.GONE);
            holder.avatarImg.setImageDrawable(null);
            holder.avatarText.setVisibility(View.VISIBLE);
            holder.avatarText.setText(avatarLetter(name));
        }

        holder.itemView.setOnClickListener(v -> listener.onServerClicked(c));
        holder.itemView.setOnLongClickListener(
                v -> {
                    listener.onServerLongClicked(c);
                    return true;
                });
    }

    @Override
    public int getItemCount() {
        return servers.size();
    }

    static final class Vh extends RecyclerView.ViewHolder {
        final ImageView avatarImg;
        final TextView avatarText;
        final TextView name;
        final TextView remark;

        Vh(@NonNull View itemView) {
            super(itemView);
            avatarImg = itemView.findViewById(R.id.server_avatar_img);
            avatarText = itemView.findViewById(R.id.server_avatar_text);
            name = itemView.findViewById(R.id.server_name);
            remark = itemView.findViewById(R.id.server_remark);
        }
    }

    private static String safe(String s) {
        return s != null ? s.trim() : "";
    }

    private static String avatarLetter(String name) {
        String n = safe(name);
        if (n.isEmpty()) return "?";
        String first = n.substring(0, 1);
        return first.toUpperCase();
    }
}

