package com.linplayer.tvlegacy.backend;

import com.linplayer.tvlegacy.Episode;
import com.linplayer.tvlegacy.Show;
import java.util.List;

public interface MediaBackend {
    void listShows(Callback<List<Show>> cb);

    void getShow(String showId, Callback<Show> cb);

    void listEpisodes(String showId, Callback<List<Episode>> cb);

    void getEpisode(String showId, int episodeIndex, Callback<Episode> cb);
}

