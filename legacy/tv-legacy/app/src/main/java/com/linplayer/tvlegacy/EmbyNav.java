package com.linplayer.tvlegacy;

import android.app.Activity;
import android.content.Intent;
import android.widget.Toast;
import com.linplayer.tvlegacy.emby.EmbyItem;
import com.linplayer.tvlegacy.emby.EmbyView;
import com.linplayer.tvlegacy.servers.ServerConfig;
import com.linplayer.tvlegacy.servers.ServerStore;

final class EmbyNav {
    private EmbyNav() {}

    static void openItem(Activity activity, EmbyItem item) {
        if (activity == null || item == null) return;
        ServerConfig active = ServerStore.getActive(activity);
        if (active == null || safe(active.baseUrl).isEmpty() || safe(active.apiKey).isEmpty()) {
            Toast.makeText(activity, "Missing server config", Toast.LENGTH_LONG).show();
            return;
        }

        if (item.isType("Series") || item.isType("Movie") || item.isType("Episode")) {
            Intent i = new Intent(activity, ItemDetailActivity.class);
            i.putExtra(ItemDetailActivity.EXTRA_ITEM_ID, item.id);
            i.putExtra(ItemDetailActivity.EXTRA_ITEM_TYPE, item.type);
            if (item.playbackPositionMs > 0L) {
                i.putExtra(ItemDetailActivity.EXTRA_POSITION_MS, item.playbackPositionMs);
            }
            activity.startActivity(i);
            return;
        }

        Toast.makeText(activity, "Unsupported item type: " + safe(item.type), Toast.LENGTH_SHORT)
                .show();
    }

    static void openView(Activity activity, EmbyView view) {
        if (activity == null || view == null) return;
        if (safe(view.id).isEmpty()) return;
        Intent i = new Intent(activity, LibraryDetailActivity.class);
        i.putExtra(LibraryDetailActivity.EXTRA_VIEW_ID, view.id);
        i.putExtra(LibraryDetailActivity.EXTRA_VIEW_NAME, view.name);
        activity.startActivity(i);
    }

    private static String safe(String s) {
        return s != null ? s.trim() : "";
    }
}
