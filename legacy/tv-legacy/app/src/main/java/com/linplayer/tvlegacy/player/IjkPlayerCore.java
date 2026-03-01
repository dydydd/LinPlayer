package com.linplayer.tvlegacy.player;

import android.content.Context;
import android.media.AudioManager;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import java.io.IOException;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import tv.danmaku.ijk.media.player.IjkMediaPlayer;

final class IjkPlayerCore implements PlayerCore {
    private static volatile boolean libsLoaded = false;

    private final Context appContext;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final SurfaceView surfaceView;

    @Nullable private Listener listener;
    @Nullable private IjkMediaPlayer player;
    private boolean playWhenReady = false;
    private long pendingSeekMs = 0L;

    IjkPlayerCore(@NonNull Context context) {
        appContext = context.getApplicationContext();
        surfaceView = new SurfaceView(context);
        surfaceView.getHolder()
                .addCallback(
                        new SurfaceHolder.Callback() {
                            @Override
                            public void surfaceCreated(SurfaceHolder holder) {
                                IjkMediaPlayer p = player;
                                if (p == null) return;
                                try {
                                    p.setDisplay(holder);
                                } catch (Exception ignored) {
                                }
                            }

                            @Override
                            public void surfaceChanged(
                                    SurfaceHolder holder, int format, int width, int height) {}

                            @Override
                            public void surfaceDestroyed(SurfaceHolder holder) {
                                IjkMediaPlayer p = player;
                                if (p == null) return;
                                try {
                                    p.setDisplay(null);
                                } catch (Exception ignored) {
                                }
                            }
                        });
        loadLibsOnce();
    }

    @Override
    @NonNull
    public PlayerCoreType getType() {
        return PlayerCoreType.IJK;
    }

    @Override
    @NonNull
    public String getDisplayName() {
        return getType().displayName;
    }

    @Override
    @NonNull
    public View getView() {
        return surfaceView;
    }

    @Override
    public void setListener(@Nullable Listener listener) {
        this.listener = listener;
    }

    @Override
    public void open(
            @NonNull String url,
            @Nullable Map<String, String> headers,
            long startPositionMs,
            boolean playWhenReady) {
        releaseInternal();

        this.playWhenReady = playWhenReady;
        pendingSeekMs = Math.max(0L, startPositionMs);

        IjkMediaPlayer p = new IjkMediaPlayer();
        player = p;
        p.setAudioStreamType(AudioManager.STREAM_MUSIC);

        p.setOnPreparedListener(
                mp -> {
                    long seek = pendingSeekMs;
                    if (seek > 0L) {
                        try {
                            mp.seekTo(seek);
                        } catch (Exception ignored) {
                        }
                    }
                    if (this.playWhenReady) {
                        try {
                            mp.start();
                        } catch (Exception ignored) {
                        }
                    }
                    notifyTracksChanged();
                });

        p.setOnErrorListener(
                (mp, what, extra) -> {
                    notifyFatalError("IjkPlayer error what=" + what + " extra=" + extra);
                    return true;
                });

        p.setOnCompletionListener(mp -> notifyTracksChanged());

        try {
            Uri uri = Uri.parse(url);
            if (headers != null && !headers.isEmpty()) {
                p.setDataSource(appContext, uri, headers);
            } else {
                p.setDataSource(appContext, uri);
            }
            try {
                p.setDisplay(surfaceView.getHolder());
            } catch (Exception ignored) {
            }
            p.prepareAsync();
        } catch (IOException e) {
            notifyFatalError(String.valueOf(e.getMessage()));
        } catch (Exception e) {
            notifyFatalError(String.valueOf(e.getMessage()));
        }
    }

    @Override
    public void play() {
        playWhenReady = true;
        IjkMediaPlayer p = player;
        if (p == null) return;
        try {
            p.start();
        } catch (Exception ignored) {
        }
    }

    @Override
    public void pause() {
        playWhenReady = false;
        IjkMediaPlayer p = player;
        if (p == null) return;
        try {
            p.pause();
        } catch (Exception ignored) {
        }
    }

    @Override
    public void stop() {
        playWhenReady = false;
        IjkMediaPlayer p = player;
        if (p == null) return;
        try {
            p.stop();
        } catch (Exception ignored) {
        }
    }

    @Override
    public void seekTo(long positionMs) {
        long ms = Math.max(0L, positionMs);
        pendingSeekMs = ms;

        IjkMediaPlayer p = player;
        if (p == null) return;
        try {
            p.seekTo(ms);
        } catch (Exception ignored) {
        }
    }

    @Override
    public boolean isPlaying() {
        IjkMediaPlayer p = player;
        if (p == null) return false;
        try {
            return p.isPlaying();
        } catch (Exception ignored) {
            return false;
        }
    }

    @Override
    public long getDurationMs() {
        IjkMediaPlayer p = player;
        if (p == null) return 0L;
        try {
            long d = p.getDuration();
            return d > 0L ? d : 0L;
        } catch (Exception ignored) {
            return 0L;
        }
    }

    @Override
    public long getPositionMs() {
        IjkMediaPlayer p = player;
        if (p == null) return 0L;
        try {
            long v = p.getCurrentPosition();
            return v > 0L ? v : 0L;
        } catch (Exception ignored) {
            return 0L;
        }
    }

    @Override
    public long getBufferedPositionMs() {
        // ijkplayer buffering APIs vary across builds/artifacts; keep it simple.
        return getPositionMs();
    }

    @Override
    @NonNull
    public List<PlayerTrack> getAudioTracks() {
        return Collections.emptyList();
    }

    @Override
    @NonNull
    public List<PlayerTrack> getSubtitleTracks() {
        return Collections.emptyList();
    }

    @Override
    public void selectAudioTrack(@Nullable Integer trackId) {}

    @Override
    public void setSubtitlesEnabled(boolean enabled) {}

    @Override
    public void selectSubtitleTrack(@Nullable Integer trackId) {}

    @Override
    public void release() {
        releaseInternal();
    }

    private void releaseInternal() {
        IjkMediaPlayer p = player;
        player = null;
        if (p == null) return;
        try {
            p.setDisplay(null);
        } catch (Exception ignored) {
        }
        try {
            p.stop();
        } catch (Exception ignored) {
        }
        try {
            p.release();
        } catch (Exception ignored) {
        }
    }

    private void notifyTracksChanged() {
        Listener l = listener;
        if (l == null) return;
        main.post(
                () -> {
                    Listener l2 = listener;
                    if (l2 != null) l2.onTracksChanged();
                });
    }

    private void notifyFatalError(@NonNull String message) {
        Listener l = listener;
        if (l == null) return;
        main.post(
                () -> {
                    Listener l2 = listener;
                    if (l2 != null) l2.onFatalError(message);
                });
    }

    private static void loadLibsOnce() {
        if (libsLoaded) return;
        synchronized (IjkPlayerCore.class) {
            if (libsLoaded) return;
            try {
                IjkMediaPlayer.loadLibrariesOnce(null);
            } catch (Throwable ignored) {
            }
            try {
                IjkMediaPlayer.native_profileBegin("libijkplayer.so");
            } catch (Throwable ignored) {
            }
            libsLoaded = true;
        }
    }
}
