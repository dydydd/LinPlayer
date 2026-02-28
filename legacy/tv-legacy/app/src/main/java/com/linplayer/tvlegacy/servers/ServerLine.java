package com.linplayer.tvlegacy.servers;

import org.json.JSONException;
import org.json.JSONObject;

public final class ServerLine {
    public final String name;
    public final String url;

    public ServerLine(String name, String url) {
        this.name = safeTrim(name);
        this.url = safeTrim(url);
    }

    public static ServerLine fromJson(JSONObject o) throws JSONException {
        if (o == null) return null;
        return new ServerLine(o.optString("name", ""), o.optString("url", ""));
    }

    public JSONObject toJson() throws JSONException {
        JSONObject o = new JSONObject();
        o.put("name", safeTrim(name));
        o.put("url", safeTrim(url));
        return o;
    }

    private static String safeTrim(String s) {
        return s != null ? s.trim() : "";
    }
}

