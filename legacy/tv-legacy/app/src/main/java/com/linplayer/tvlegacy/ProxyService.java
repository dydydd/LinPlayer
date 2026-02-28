package com.linplayer.tvlegacy;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import java.io.IOException;

public final class ProxyService extends Service {
    static final String ACTION_START = "com.linplayer.tvlegacy.action.START_PROXY";
    static final String ACTION_STOP = "com.linplayer.tvlegacy.action.STOP_PROXY";
    static final String ACTION_APPLY_CONFIG = "com.linplayer.tvlegacy.action.APPLY_CONFIG";
    static final String ACTION_STATUS = "com.linplayer.tvlegacy.action.STATUS";

    static final String EXTRA_STATUS = "status";

    private static final String CHANNEL_ID = "proxy";
    private static final int NOTIFICATION_ID = 1;

    private final MihomoProcess mihomo = new MihomoProcess();
    private String lastStatus = "stopped";

    public static void start(Context context) {
        Intent intent = new Intent(context, ProxyService.class);
        intent.setAction(ACTION_START);
        startServiceCompat(context, intent);
    }

    public static void stop(Context context) {
        Intent intent = new Intent(context, ProxyService.class);
        intent.setAction(ACTION_STOP);
        startServiceCompat(context, intent);
    }

    public static void applyConfig(Context context) {
        Intent intent = new Intent(context, ProxyService.class);
        intent.setAction(ACTION_APPLY_CONFIG);
        startServiceCompat(context, intent);
    }

    public static void requestStatusBroadcast(Context context) {
        Intent i = new Intent(ACTION_STATUS);
        i.setPackage(context.getPackageName());
        i.putExtra(EXTRA_STATUS, AppPrefs.getLastStatus(context));
        context.sendBroadcast(i);
    }

    private static void startServiceCompat(Context context, Intent intent) {
        String action = intent.getAction();
        boolean needsForeground = ACTION_START.equals(action);
        if (needsForeground && Build.VERSION.SDK_INT >= 26) {
            context.startForegroundService(intent);
            return;
        }
        context.startService(intent);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent != null ? intent.getAction() : null;
        if (ACTION_STOP.equals(action)) {
            lastStatus = mihomo.stop();
            AppPrefs.setLastStatus(this, lastStatus);
            ProxyEnv.disable();
            stopForegroundCompat();
            broadcastStatus(lastStatus);
            stopSelf();
            return START_NOT_STICKY;
        }

        if (ACTION_APPLY_CONFIG.equals(action)) {
            try {
                MihomoConfig.ensureWritten(this);
                if (mihomo.isRunning() && AppPrefs.isProxyEnabled(this)) {
                    lastStatus = mihomo.restart(this);
                } else {
                    lastStatus = "config saved";
                }
            } catch (IOException e) {
                lastStatus = "config write failed: " + e.getMessage();
            }
            if (mihomo.isRunning() && AppPrefs.isProxyEnabled(this)) {
                ProxyEnv.enable();
            }
            AppPrefs.setLastStatus(this, lastStatus);
            broadcastStatus(lastStatus);
            if (!mihomo.isRunning()) {
                stopSelf();
            }
            return START_NOT_STICKY;
        }

        // Default: start proxy.
        ensureForeground();
        try {
            MihomoConfig.ensureWritten(this);
            lastStatus = mihomo.start(this);
        } catch (IOException e) {
            lastStatus = "config write failed: " + e.getMessage();
        }
        if (mihomo.isRunning() && AppPrefs.isProxyEnabled(this)) {
            ProxyEnv.enable();
        }
        AppPrefs.setLastStatus(this, lastStatus);
        broadcastStatus(lastStatus);
        return START_STICKY;
    }

    private void broadcastStatus(String status) {
        Intent i = new Intent(ACTION_STATUS);
        i.setPackage(getPackageName());
        i.putExtra(EXTRA_STATUS, status);
        sendBroadcast(i);
    }

    private void ensureForeground() {
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (nm == null) return;

        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel =
                    new NotificationChannel(
                            CHANNEL_ID,
                            "Proxy",
                            NotificationManager.IMPORTANCE_LOW);
            nm.createNotificationChannel(channel);
        }

        Notification n =
                new NotificationCompat.Builder(this, CHANNEL_ID)
                        .setSmallIcon(android.R.drawable.stat_sys_download_done)
                        .setContentTitle("LinPlayer TV Legacy")
                        .setContentText("Proxy service running")
                        .setOngoing(true)
                        .build();

        startForeground(NOTIFICATION_ID, n);
    }

    private void stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= 24) {
            stopForeground(STOP_FOREGROUND_REMOVE);
        } else {
            //noinspection deprecation
            stopForeground(true);
        }
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onDestroy() {
        try {
            lastStatus = mihomo.stop();
            AppPrefs.setLastStatus(this, lastStatus);
        } catch (Exception ignored) {
            // ignore
        } finally {
            ProxyEnv.disable();
        }
        super.onDestroy();
    }
}
