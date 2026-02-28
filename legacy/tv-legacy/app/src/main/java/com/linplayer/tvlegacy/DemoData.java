package com.linplayer.tvlegacy;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class DemoData {
    private DemoData() {}

    public static List<Show> shows() {
        List<Show> list = new ArrayList<>();
        list.add(
                new Show(
                        "demo_a",
                        "Demo Show A",
                        "This is a placeholder show used to validate TV UI and navigation on API 19."));
        list.add(
                new Show(
                        "demo_b",
                        "Demo Show B",
                        "Replace this demo data with your real library later (Emby/Jellyfin/WebDAV)."));
        list.add(new Show("demo_c", "Demo Show C", "Focus, DPAD, and playback skeleton."));
        list.add(new Show("demo_d", "Demo Show D", "Proxy on/off should affect playback requests."));
        list.add(new Show("demo_e", "Demo Show E", "Settings UI will be refined later."));
        return Collections.unmodifiableList(list);
    }

    public static Show findShow(String showId) {
        if (showId == null) return null;
        for (Show s : shows()) {
            if (showId.equals(s.id)) return s;
        }
        return null;
    }

    public static List<Episode> episodes(String showId) {
        // A public sample mp4 for development only.
        // Replace with real episode URLs later.
        String sample =
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4";

        List<Episode> list = new ArrayList<>();
        if (showId == null) return Collections.unmodifiableList(list);

        for (int i = 1; i <= 12; i++) {
            list.add(new Episode(showId + "_ep_" + i, i, "Episode " + i, sample));
        }
        return Collections.unmodifiableList(list);
    }
}
