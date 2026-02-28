package com.linplayer.tvlegacy.backend;

import android.os.Handler;
import android.os.Looper;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class AppExecutors {
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private AppExecutors() {}

    static void io(Runnable r) {
        IO.execute(r);
    }

    static void main(Runnable r) {
        MAIN.post(r);
    }
}

