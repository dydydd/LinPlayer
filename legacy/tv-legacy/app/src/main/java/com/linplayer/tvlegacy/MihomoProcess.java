package com.linplayer.tvlegacy;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.os.Build;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;

final class MihomoProcess {
    private static final String NATIVE_NAME = "libmihomo.so";

    private Process process;

    boolean isRunning() {
        return process != null;
    }

    String start(Context context) {
        if (process != null) return "mihomo already running";

        ApplicationInfo appInfo = context.getApplicationInfo();
        File nativeDir = new File(appInfo.nativeLibraryDir);
        File exe = new File(nativeDir, NATIVE_NAME);

        if (!exe.exists()) {
            return "mihomo not found: " + exe.getAbsolutePath();
        }

        // Best-effort: execute permission may be required on some ROMs/filesystems.
        // When packaged in nativeLibraryDir, many devices allow exec directly.
        // Note: File#setExecutable is available since API 9.
        //noinspection ResultOfMethodCallIgnored
        exe.setExecutable(true, true);

        File workDir = MihomoConfig.baseDir(context);

        try {
            ProcessBuilder pb =
                    new ProcessBuilder(exe.getAbsolutePath(), "-d", workDir.getAbsolutePath());
            pb.directory(workDir);
            pb.redirectErrorStream(true);
            process = pb.start();
            drainOutputAsync(process);
            return "mihomo started (pid unknown on API " + Build.VERSION.SDK_INT + ")";
        } catch (IOException e) {
            process = null;
            return "mihomo start failed: " + e.getMessage();
        }
    }

    private static void drainOutputAsync(Process p) {
        Thread t =
                new Thread(
                        () -> {
                            InputStream in = null;
                            try {
                                in = p.getInputStream();
                                byte[] buf = new byte[8192];
                                //noinspection StatementWithEmptyBody
                                while (in.read(buf) >= 0) {}
                            } catch (IOException ignored) {
                                // ignore
                            } finally {
                                if (in != null) {
                                    try {
                                        in.close();
                                    } catch (IOException ignored) {
                                        // ignore
                                    }
                                }
                            }
                        },
                        "mihomo-output");
        t.setDaemon(true);
        t.start();
    }

    String restart(Context context) {
        stop();
        return start(context);
    }

    String stop() {
        if (process == null) return "mihomo not running";
        try {
            final Process p = process;
            p.destroy();

            // Best-effort: give it a short moment to exit, without blocking indefinitely.
            Thread waiter =
                    new Thread(
                            () -> {
                                try {
                                    p.waitFor();
                                } catch (InterruptedException ignored) {
                                    // ignore
                                }
                            },
                            "mihomo-waiter");
            waiter.setDaemon(true);
            waiter.start();
            try {
                waiter.join(1500);
            } catch (InterruptedException ignored) {
                // ignore
            }
        } catch (Exception ignored) {
            // ignore
        } finally {
            process = null;
        }
        return "mihomo stopped";
    }
}
