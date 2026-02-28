package com.linplayer.tvlegacy.backend;

public interface Callback<T> {
    void onSuccess(T value);

    void onError(Throwable error);
}

