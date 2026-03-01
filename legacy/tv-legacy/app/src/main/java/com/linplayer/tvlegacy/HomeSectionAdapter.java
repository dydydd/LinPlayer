package com.linplayer.tvlegacy;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.linplayer.tvlegacy.emby.EmbyItem;
import com.linplayer.tvlegacy.emby.EmbyView;
import java.util.ArrayList;
import java.util.List;

final class HomeSectionAdapter extends RecyclerView.Adapter<HomeSectionAdapter.Vh> {
    interface Listener {
        void onItemClicked(EmbyItem item);

        void onViewClicked(EmbyView view);
    }

    private final Listener listener;
    private final RecyclerView.RecycledViewPool sharedPool = new RecyclerView.RecycledViewPool();
    private final List<HomeSection> sections = new ArrayList<>();

    private int panelAlpha255 = 255;

    HomeSectionAdapter(Listener listener) {
        this.listener = listener;
    }

    void setPanelAlpha255(int alpha255) {
        this.panelAlpha255 = clamp(alpha255, 0, 255);
        notifyDataSetChanged();
    }

    void setSections(List<HomeSection> list) {
        sections.clear();
        if (list != null) sections.addAll(list);
        notifyDataSetChanged();
    }

    @NonNull
    @Override
    public Vh onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View v =
                LayoutInflater.from(parent.getContext())
                        .inflate(R.layout.item_home_section, parent, false);
        return new Vh(v, sharedPool, listener);
    }

    @Override
    public void onBindViewHolder(@NonNull Vh holder, int position) {
        HomeSection section = sections.get(position);
        holder.title.setText(section != null ? section.title : "");

        int alpha = panelAlpha255;

        if (section == null) return;
        if (section.type == HomeSection.TYPE_VIEWS) {
            EmbyViewAdapter adapter = holder.viewAdapter;
            adapter.setData(section.views, 220, alpha);
            if (holder.list.getAdapter() != adapter) {
                holder.list.setAdapter(adapter);
            }
        } else {
            EmbyCardAdapter adapter = holder.itemAdapter;
            int mode =
                    section.type == HomeSection.TYPE_RESUME
                            ? EmbyCardAdapter.MODE_RESUME
                            : EmbyCardAdapter.MODE_NORMAL;
            int widthDp = section.type == HomeSection.TYPE_RESUME ? 220 : 200;
            adapter.setData(section.items, mode, widthDp, alpha);
            if (holder.list.getAdapter() != adapter) {
                holder.list.setAdapter(adapter);
            }
        }
    }

    @Override
    public int getItemCount() {
        return sections.size();
    }

    static final class Vh extends RecyclerView.ViewHolder {
        final TextView title;
        final RecyclerView list;
        final EmbyCardAdapter itemAdapter;
        final EmbyViewAdapter viewAdapter;

        Vh(@NonNull View itemView, RecyclerView.RecycledViewPool pool, Listener listener) {
            super(itemView);
            title = itemView.findViewById(R.id.section_title);
            list = itemView.findViewById(R.id.section_list);
            list.setLayoutManager(
                    new LinearLayoutManager(itemView.getContext(), LinearLayoutManager.HORIZONTAL, false));
            list.setRecycledViewPool(pool);
            list.setNestedScrollingEnabled(false);
            list.setItemAnimator(null);
            list.addItemDecoration(
                    new HorizontalSpacingItemDecoration(dpToPx(itemView, 12), true));

            itemAdapter =
                    new EmbyCardAdapter(
                            item -> {
                                if (listener != null) listener.onItemClicked(item);
                            });
            viewAdapter =
                    new EmbyViewAdapter(
                            view -> {
                                if (listener != null) listener.onViewClicked(view);
                            });
        }

        private static int dpToPx(View view, int dp) {
            float density = view.getResources().getDisplayMetrics().density;
            return Math.round(dp * density);
        }
    }

    @Override
    public void onAttachedToRecyclerView(@NonNull RecyclerView recyclerView) {
        super.onAttachedToRecyclerView(recyclerView);
        // nothing
    }

    private static int clamp(int v, int min, int max) {
        return v < min ? min : (v > max ? max : v);
    }

    @Override
    public void onViewAttachedToWindow(@NonNull Vh holder) {
        super.onViewAttachedToWindow(holder);
        // no-op
    }
}
