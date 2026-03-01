package com.linplayer.tvlegacy;

import android.graphics.Rect;
import android.view.View;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

final class HorizontalSpacingItemDecoration extends RecyclerView.ItemDecoration {
    private final int spacingPx;
    private final boolean includeEdge;

    HorizontalSpacingItemDecoration(int spacingPx, boolean includeEdge) {
        this.spacingPx = Math.max(0, spacingPx);
        this.includeEdge = includeEdge;
    }

    @Override
    public void getItemOffsets(
            @NonNull Rect outRect,
            @NonNull View view,
            @NonNull RecyclerView parent,
            @NonNull RecyclerView.State state) {
        int position = parent.getChildAdapterPosition(view);
        if (position == RecyclerView.NO_POSITION) return;
        int s = spacingPx;
        if (s <= 0) return;

        outRect.top = 0;
        outRect.bottom = 0;
        outRect.right = s;
        outRect.left = includeEdge && position == 0 ? s : 0;
    }
}

