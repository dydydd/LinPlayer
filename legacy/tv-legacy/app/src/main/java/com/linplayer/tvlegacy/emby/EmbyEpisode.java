package com.linplayer.tvlegacy.emby;

public final class EmbyEpisode {
    public final String id;
    public final String name;
    public final int seasonNumber;
    public final int episodeNumber;
    public final String premiereDate;
    public final long runtimeTicks;
    public final boolean played;
    public final long playbackPositionMs;

    public EmbyEpisode(
            String id,
            String name,
            int seasonNumber,
            int episodeNumber,
            String premiereDate,
            long runtimeTicks,
            boolean played,
            long playbackPositionMs) {
        this.id = safeTrim(id);
        this.name = safeTrim(name);
        this.seasonNumber = Math.max(0, seasonNumber);
        this.episodeNumber = Math.max(0, episodeNumber);
        this.premiereDate = safeTrim(premiereDate);
        this.runtimeTicks = Math.max(0L, runtimeTicks);
        this.played = played;
        this.playbackPositionMs = Math.max(0L, playbackPositionMs);
    }

    public EmbyEpisode withPlayed(boolean played) {
        return new EmbyEpisode(
                id, name, seasonNumber, episodeNumber, premiereDate, runtimeTicks, played, playbackPositionMs);
    }

    private static String safeTrim(String s) {
        return s != null ? s.trim() : "";
    }
}

