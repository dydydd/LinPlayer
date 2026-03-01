package com.linplayer.tvlegacy.emby;

import java.util.Locale;

public final class EmbyItemDetails {
    public final String id;
    public final String type;
    public final String name;
    public final String overview;

    public final String seriesId;
    public final String seriesName;
    public final int seasonNumber;
    public final int episodeNumber;

    public final String premiereDate;
    public final long runtimeTicks;

    public final boolean isFavorite;
    public final boolean played;
    public final long playbackPositionMs;

    public EmbyItemDetails(
            String id,
            String type,
            String name,
            String overview,
            String seriesId,
            String seriesName,
            int seasonNumber,
            int episodeNumber,
            String premiereDate,
            long runtimeTicks,
            boolean isFavorite,
            boolean played,
            long playbackPositionMs) {
        this.id = safeTrim(id);
        this.type = safeTrim(type);
        this.name = safeTrim(name);
        this.overview = safe(overview);

        this.seriesId = safeTrim(seriesId);
        this.seriesName = safeTrim(seriesName);
        this.seasonNumber = Math.max(0, seasonNumber);
        this.episodeNumber = Math.max(0, episodeNumber);

        this.premiereDate = safeTrim(premiereDate);
        this.runtimeTicks = Math.max(0L, runtimeTicks);

        this.isFavorite = isFavorite;
        this.played = played;
        this.playbackPositionMs = Math.max(0L, playbackPositionMs);
    }

    public boolean isType(String t) {
        if (t == null) return false;
        return type.equalsIgnoreCase(t.trim());
    }

    public String displayTitle() {
        if (isType("Episode")) {
            String show = safeTrim(seriesName);
            String se = formatSeasonEpisode(seasonNumber, episodeNumber);
            if (!show.isEmpty() && !se.isEmpty()) return show + " " + se;
        }
        return !name.isEmpty() ? name : id;
    }

    private static String formatSeasonEpisode(int season, int episode) {
        if (season <= 0 && episode <= 0) return "";
        if (season <= 0) return "E" + episode;
        if (episode <= 0) return "S" + season;
        return String.format(Locale.US, "S%02dE%02d", season, episode);
    }

    private static String safeTrim(String s) {
        return s != null ? s.trim() : "";
    }

    private static String safe(String s) {
        return s != null ? s : "";
    }
}

