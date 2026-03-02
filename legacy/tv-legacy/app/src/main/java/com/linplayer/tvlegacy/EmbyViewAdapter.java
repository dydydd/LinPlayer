package com.linplayer.tvlegacy;

import android.content.Context;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import com.linplayer.tvlegacy.emby.EmbyView;
import java.util.Collections;
import java.util.List;

final class EmbyViewAdapter extends RecyclerView.Adapter<EmbyViewAdapter.Vh> {
    interface Listener {
        void onViewClicked(EmbyView view);
    }

    private final Listener listener;
    private List<EmbyView> views = Collections.emptyList();
    private int itemWidthDp = 0;
    private int panelAlpha255 = 255;

    EmbyViewAdapter(Listener listener) {
        this.listener = listener;
    }

    void setData(List<EmbyView> views, int itemWidthDp, int panelAlpha255) {
        this.views = views != null ? views : Collections.emptyList();
        this.itemWidthDp = Math.max(0, itemWidthDp);
        this.panelAlpha255 = clamp(panelAlpha255, 0, 255);
        notifyDataSetChanged();
    }

    @NonNull
    @Override
    public Vh onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View v =
                LayoutInflater.from(parent.getContext())
                        .inflate(R.layout.item_media_card, parent, false);
        if (itemWidthDp > 0) {
            int px = dpToPx(parent.getContext(), itemWidthDp);
            RecyclerView.LayoutParams lp = (RecyclerView.LayoutParams) v.getLayoutParams();
            lp.width = px;
            v.setLayoutParams(lp);

            ImageView img = v.findViewById(R.id.card_image);
            if (img != null) {
                ViewGroup.LayoutParams ilp = img.getLayoutParams();
                if (ilp != null) {
                    ilp.height = Math.round(px * 9f / 16f);
                    img.setLayoutParams(ilp);
                }
            }
        }
        return new Vh(v);
    }

    @Override
    public void onBindViewHolder(@NonNull Vh holder, int position) {
        EmbyView view = views.get(position);
        TvStyle.applyPanelAlpha(holder.itemView, panelAlpha255);
        holder.title.setText(view != null ? view.name : "");
        holder.subtitle.setVisibility(View.GONE);
        ImageLoader.load(holder.image, view != null ? view.imageUrl : "", 640);
        holder.itemView.setOnClickListener(v -> listener.onViewClicked(view));
    }

    @Override
    public int getItemCount() {
        return views != null ? views.size() : 0;
    }

    static final class Vh extends RecyclerView.ViewHolder {
        final ImageView image;
        final TextView title;
        final TextView subtitle;

        Vh(@NonNull View itemView) {
            super(itemView);
            image = itemView.findViewById(R.id.card_image);
            title = itemView.findViewById(R.id.card_title);
            subtitle = itemView.findViewById(R.id.card_subtitle);
        }
    }

    private static int dpToPx(Context context, int dp) {
        float density = context.getResources().getDisplayMetrics().density;
        return Math.round(dp * density);
    }

    private static int clamp(int v, int min, int max) {
        return v < min ? min : (v > max ? max : v);
    }
}
