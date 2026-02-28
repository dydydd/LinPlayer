package com.linplayer.tvlegacy.backend;

import com.linplayer.tvlegacy.DemoData;
import com.linplayer.tvlegacy.Episode;
import com.linplayer.tvlegacy.Show;
import java.util.List;

final class DemoMediaBackend implements MediaBackend {
    @Override
    public void listShows(Callback<List<Show>> cb) {
        AppExecutors.io(
                () -> {
                    try {
                        List<Show> v = DemoData.shows();
                        AppExecutors.main(() -> cb.onSuccess(v));
                    } catch (Exception e) {
                        AppExecutors.main(() -> cb.onError(e));
                    }
                });
    }

    @Override
    public void getShow(String showId, Callback<Show> cb) {
        AppExecutors.io(
                () -> {
                    try {
                        Show v = DemoData.findShow(showId);
                        AppExecutors.main(() -> cb.onSuccess(v));
                    } catch (Exception e) {
                        AppExecutors.main(() -> cb.onError(e));
                    }
                });
    }

    @Override
    public void listEpisodes(String showId, Callback<List<Episode>> cb) {
        AppExecutors.io(
                () -> {
                    try {
                        List<Episode> v = DemoData.episodes(showId);
                        AppExecutors.main(() -> cb.onSuccess(v));
                    } catch (Exception e) {
                        AppExecutors.main(() -> cb.onError(e));
                    }
                });
    }

    @Override
    public void getEpisode(String showId, int episodeIndex, Callback<Episode> cb) {
        AppExecutors.io(
                () -> {
                    try {
                        Episode found = null;
                        List<Episode> list = DemoData.episodes(showId);
                        for (Episode e : list) {
                            if (e.index == episodeIndex) {
                                found = e;
                                break;
                            }
                        }
                        Episode v = found;
                        AppExecutors.main(() -> cb.onSuccess(v));
                    } catch (Exception e) {
                        AppExecutors.main(() -> cb.onError(e));
                    }
                });
    }
}

