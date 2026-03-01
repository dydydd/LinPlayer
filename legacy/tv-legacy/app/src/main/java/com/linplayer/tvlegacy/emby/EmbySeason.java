package com.linplayer.tvlegacy.emby;

public final class EmbySeason {
    public final String id;
    public final int seasonNumber;
    public final String name;

    public EmbySeason(String id, int seasonNumber, String name) {
        this.id = safeTrim(id);
        this.seasonNumber = Math.max(0, seasonNumber);
        this.name = safeTrim(name);
    }

    private static String safeTrim(String s) {
        return s != null ? s.trim() : "";
    }
}

