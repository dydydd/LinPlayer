// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import static androidx.media3.common.Player.REPEAT_MODE_ALL;
import static androidx.media3.common.Player.REPEAT_MODE_OFF;

import android.graphics.Color;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.View;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.TrackGroup;
import androidx.media3.common.TrackSelectionOverride;
import androidx.media3.common.Tracks;
import androidx.media3.common.text.Cue;
import androidx.media3.common.text.CueGroup;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;
import androidx.media3.ui.CaptionStyleCompat;
import androidx.media3.ui.SubtitleView;
import io.flutter.view.TextureRegistry.SurfaceProducer;
import java.io.File;
import java.util.ArrayList;
import java.util.List;

/**
 * A class responsible for managing video playback using {@link ExoPlayer}.
 *
 * <p>It provides methods to control playback, adjust volume, and handle seeking.
 */
public abstract class VideoPlayer implements VideoPlayerInstanceApi {
  @NonNull protected final VideoPlayerCallbacks videoPlayerEvents;
  @Nullable protected final SurfaceProducer surfaceProducer;
  @Nullable private DisposeHandler disposeHandler;
  @NonNull protected ExoPlayer exoPlayer;
  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi @Nullable protected DefaultTrackSelector trackSelector;

  // Subtitle state for LinPlayer.
  @NonNull private final Handler mainHandler = new Handler(Looper.getMainLooper());
  @Nullable private SubtitleView platformSubtitleView;
  @NonNull private List<Cue> subtitleCues = new ArrayList<>();
  @NonNull private String subtitleText = "";
  @Nullable private Runnable pendingSubtitleUpdate;
  private long subtitleDelayMs = 0;
  private double subtitleFontSize = 18.0;
  private double subtitleBottomPadding = 24.0;
  private boolean subtitleBold = false;
  private boolean disposed = false;

  @NonNull
  private final androidx.media3.common.Player.Listener subtitleListener =
      new androidx.media3.common.Player.Listener() {
        @Override
        public void onCues(@NonNull CueGroup cueGroup) {
          final String text = cueGroupToText(cueGroup);
          scheduleSubtitleUpdate(new ArrayList<>(cueGroup.cues), text);
        }
      };

  /** A closure-compatible signature since {@link java.util.function.Supplier} is API level 24. */
  public interface ExoPlayerProvider {
    /**
     * Returns a new {@link ExoPlayer}.
     *
     * @return new instance.
     */
    @NonNull
    ExoPlayer get();
  }

  /** A handler to run when dispose is called. */
  public interface DisposeHandler {
    void onDispose();
  }

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  // Error thrown for this-escape warning on JDK 21+ due to https://bugs.openjdk.org/browse/JDK-8015831.
  // Keeping behavior as-is and addressing the warning could cause a regression: https://github.com/flutter/packages/pull/10193
  @SuppressWarnings("this-escape")
  public VideoPlayer(
      @NonNull VideoPlayerCallbacks events,
      @NonNull MediaItem mediaItem,
      @NonNull VideoPlayerOptions options,
      @Nullable SurfaceProducer surfaceProducer,
      @NonNull ExoPlayerProvider exoPlayerProvider) {
    this.videoPlayerEvents = events;
    this.surfaceProducer = surfaceProducer;
    exoPlayer = exoPlayerProvider.get();

    // Try to get the track selector from the ExoPlayer if it was built with one
    if (exoPlayer.getTrackSelector() instanceof DefaultTrackSelector) {
      trackSelector = (DefaultTrackSelector) exoPlayer.getTrackSelector();
    }

    exoPlayer.setMediaItem(mediaItem);
    exoPlayer.prepare();
    exoPlayer.addListener(createExoPlayerEventListener(exoPlayer, surfaceProducer));
    exoPlayer.addListener(subtitleListener);
    setAudioAttributes(exoPlayer, options.mixWithOthers);
  }

  public void setDisposeHandler(@Nullable DisposeHandler handler) {
    disposeHandler = handler;
  }

  @NonNull
  protected abstract ExoPlayerEventListener createExoPlayerEventListener(
      @NonNull ExoPlayer exoPlayer, @Nullable SurfaceProducer surfaceProducer);

  private static void setAudioAttributes(ExoPlayer exoPlayer, boolean isMixMode) {
    exoPlayer.setAudioAttributes(
        new AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
        !isMixMode);
  }

  @Override
  public void play() {
    exoPlayer.play();
  }

  @Override
  public void pause() {
    exoPlayer.pause();
  }

  @Override
  public void setLooping(boolean looping) {
    exoPlayer.setRepeatMode(looping ? REPEAT_MODE_ALL : REPEAT_MODE_OFF);
  }

  @Override
  public void setVolume(double volume) {
    float bracketedValue = (float) Math.max(0.0, Math.min(1.0, volume));
    exoPlayer.setVolume(bracketedValue);
  }

  @Override
  public void setPlaybackSpeed(double speed) {
    // We do not need to consider pitch and skipSilence for now as we do not handle them and
    // therefore never diverge from the default values.
    final PlaybackParameters playbackParameters = new PlaybackParameters((float) speed);

    exoPlayer.setPlaybackParameters(playbackParameters);
  }

  @Override
  public long getCurrentPosition() {
    return exoPlayer.getCurrentPosition();
  }

  @Override
  public long getBufferedPosition() {
    return exoPlayer.getBufferedPosition();
  }

  @Override
  public void seekTo(long position) {
    exoPlayer.seekTo(position);
  }

  @NonNull
  public ExoPlayer getExoPlayer() {
    return exoPlayer;
  }

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @Override
  public @NonNull NativeAudioTrackData getAudioTracks() {
    List<ExoPlayerAudioTrackData> audioTracks = new ArrayList<>();

    // Get the current tracks from ExoPlayer
    Tracks tracks = exoPlayer.getCurrentTracks();

    // Iterate through all track groups
    for (int groupIndex = 0; groupIndex < tracks.getGroups().size(); groupIndex++) {
      Tracks.Group group = tracks.getGroups().get(groupIndex);

      // Only process audio tracks
      if (group.getType() == C.TRACK_TYPE_AUDIO) {
        for (int trackIndex = 0; trackIndex < group.length; trackIndex++) {
          Format format = group.getTrackFormat(trackIndex);
          boolean isSelected = group.isTrackSelected(trackIndex);

          // Create audio track data with metadata
          ExoPlayerAudioTrackData audioTrack =
              new ExoPlayerAudioTrackData(
                  (long) groupIndex,
                  (long) trackIndex,
                  format.label,
                  format.language,
                  isSelected,
                  format.bitrate != Format.NO_VALUE ? (long) format.bitrate : null,
                  format.sampleRate != Format.NO_VALUE ? (long) format.sampleRate : null,
                  format.channelCount != Format.NO_VALUE ? (long) format.channelCount : null,
                  format.codecs != null ? format.codecs : null);

          audioTracks.add(audioTrack);
        }
      }
    }
    return new NativeAudioTrackData(audioTracks);
  }

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @Override
  public void selectAudioTrack(long groupIndex, long trackIndex) {
    if (trackSelector == null) {
      throw new IllegalStateException("Cannot select audio track: track selector is null");
    }

    // Get current tracks
    Tracks tracks = exoPlayer.getCurrentTracks();

    if (groupIndex < 0 || groupIndex >= tracks.getGroups().size()) {
      throw new IllegalArgumentException(
          "Cannot select audio track: groupIndex "
              + groupIndex
              + " is out of bounds (available groups: "
              + tracks.getGroups().size()
              + ")");
    }

    Tracks.Group group = tracks.getGroups().get((int) groupIndex);

    // Verify it's an audio track
    if (group.getType() != C.TRACK_TYPE_AUDIO) {
      throw new IllegalArgumentException(
          "Cannot select audio track: group at index "
              + groupIndex
              + " is not an audio track (type: "
              + group.getType()
              + ")");
    }

    // Verify the track index is valid
    if (trackIndex < 0 || (int) trackIndex >= group.length) {
      throw new IllegalArgumentException(
          "Cannot select audio track: trackIndex "
              + trackIndex
              + " is out of bounds (available tracks in group: "
              + group.length
              + ")");
    }

    // Get the track group and create a selection override
    TrackGroup trackGroup = group.getMediaTrackGroup();
    TrackSelectionOverride override = new TrackSelectionOverride(trackGroup, (int) trackIndex);

    // Apply the track selection override
    trackSelector.setParameters(
        trackSelector.buildUponParameters().setOverrideForType(override).build());
  }

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @Override
  public @NonNull NativeSubtitleTrackData getSubtitleTracks() {
    List<ExoPlayerSubtitleTrackData> subtitleTracks = new ArrayList<>();

    // Get the current tracks from ExoPlayer
    Tracks tracks = exoPlayer.getCurrentTracks();

    // Iterate through all track groups
    for (int groupIndex = 0; groupIndex < tracks.getGroups().size(); groupIndex++) {
      Tracks.Group group = tracks.getGroups().get(groupIndex);

      // Only process text/subtitle tracks
      if (group.getType() == C.TRACK_TYPE_TEXT) {
        for (int trackIndex = 0; trackIndex < group.length; trackIndex++) {
          Format format = group.getTrackFormat(trackIndex);
          boolean isSelected = group.isTrackSelected(trackIndex);

          // Create subtitle track data with metadata
          ExoPlayerSubtitleTrackData subtitleTrack =
              new ExoPlayerSubtitleTrackData(
                  (long) groupIndex,
                  (long) trackIndex,
                  format.label,
                  format.language,
                  isSelected,
                  format.codecs != null ? format.codecs : null,
                  format.sampleMimeType != null ? format.sampleMimeType : null);

          subtitleTracks.add(subtitleTrack);
        }
      }
    }
    return new NativeSubtitleTrackData(subtitleTracks);
  }

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @Override
  public void selectSubtitleTrack(long groupIndex, long trackIndex) {
    if (trackSelector == null) {
      throw new IllegalStateException("Cannot select subtitle track: track selector is null");
    }

    // Get current tracks
    Tracks tracks = exoPlayer.getCurrentTracks();

    if (groupIndex < 0 || groupIndex >= tracks.getGroups().size()) {
      throw new IllegalArgumentException(
          "Cannot select subtitle track: groupIndex "
              + groupIndex
              + " is out of bounds (available groups: "
              + tracks.getGroups().size()
              + ")");
    }

    Tracks.Group group = tracks.getGroups().get((int) groupIndex);

    // Verify it's a text track
    if (group.getType() != C.TRACK_TYPE_TEXT) {
      throw new IllegalArgumentException(
          "Cannot select subtitle track: group at index "
              + groupIndex
              + " is not a subtitle track (type: "
              + group.getType()
              + ")");
    }

    // Verify the track index is valid
    if (trackIndex < 0 || (int) trackIndex >= group.length) {
      throw new IllegalArgumentException(
          "Cannot select subtitle track: trackIndex "
              + trackIndex
              + " is out of bounds (available tracks in group: "
              + group.length
              + ")");
    }

    // Get the track group and create a selection override
    TrackGroup trackGroup = group.getMediaTrackGroup();
    TrackSelectionOverride override = new TrackSelectionOverride(trackGroup, (int) trackIndex);

    // Apply the track selection override and ensure subtitles are enabled.
    trackSelector.setParameters(
        trackSelector
            .buildUponParameters()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
            .setOverrideForType(override)
            .build());
  }

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @Override
  public void deselectSubtitleTrack() {
    if (trackSelector == null) {
      throw new IllegalStateException("Cannot deselect subtitle track: track selector is null");
    }

    // Clear any explicit overrides and disable text track selection.
    trackSelector.setParameters(
        trackSelector
            .buildUponParameters()
            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
            .build());
  }

  @Override
  public @NonNull String getSubtitleText() {
    return subtitleText;
  }

  @Override
  public void setSubtitleDelay(long delayMs) {
    subtitleDelayMs = Math.max(-60000, Math.min(60000, delayMs));
  }

  @Override
  public void setSubtitleStyle(@NonNull SubtitleStyleMessage style) {
    subtitleFontSize = Math.max(8.0, Math.min(96.0, style.getFontSize()));
    subtitleBottomPadding = Math.max(0.0, Math.min(500.0, style.getBottomPadding()));
    subtitleBold = style.getBold();
    final SubtitleView view = platformSubtitleView;
    if (view != null) {
      mainHandler.post(() -> applySubtitleStyle(view));
    }
  }

  @UnstableApi
  @Override
  public void addSubtitleSource(
      @NonNull String uri, @Nullable String mimeType, @Nullable String language, @Nullable String label) {
    final MediaItem current = exoPlayer.getCurrentMediaItem();
    if (current == null) {
      throw new IllegalStateException("Cannot add subtitle source: no media item loaded");
    }

    final Uri subtitleUri = toAndroidUri(uri);
    final String resolvedMimeType =
        (mimeType != null && !mimeType.trim().isEmpty()) ? mimeType : guessSubtitleMimeType(uri);

    final MediaItem.SubtitleConfiguration.Builder subBuilder =
        new MediaItem.SubtitleConfiguration.Builder(subtitleUri);
    if (resolvedMimeType != null && !resolvedMimeType.trim().isEmpty()) {
      subBuilder.setMimeType(resolvedMimeType);
    }
    if (language != null && !language.trim().isEmpty()) {
      subBuilder.setLanguage(language);
    }
    if (label != null && !label.trim().isEmpty()) {
      subBuilder.setLabel(label);
    }
    subBuilder.setSelectionFlags(C.SELECTION_FLAG_DEFAULT);
    final MediaItem.SubtitleConfiguration sub = subBuilder.build();

    final List<MediaItem.SubtitleConfiguration> subs = new ArrayList<>();
    if (current.localConfiguration != null && current.localConfiguration.subtitleConfigurations != null) {
      subs.addAll(current.localConfiguration.subtitleConfigurations);
    }
    subs.add(sub);

    final long pos = exoPlayer.getCurrentPosition();
    final boolean playWhenReady = exoPlayer.getPlayWhenReady();

    final MediaItem updated = current.buildUpon().setSubtitleConfigurations(subs).build();
    exoPlayer.setMediaItem(updated, pos);
    exoPlayer.prepare();
    exoPlayer.setPlayWhenReady(playWhenReady);

    // Ensure subtitles are enabled.
    if (trackSelector != null) {
      trackSelector.setParameters(trackSelector.buildUponParameters().setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false).build());
    }
  }

  public void setPlatformSubtitleView(@Nullable SubtitleView view) {
    platformSubtitleView = view;
    if (view == null) return;
    mainHandler.post(
        () -> {
          applySubtitleStyle(view);
          updateSubtitles(subtitleCues, subtitleText);
        });
  }

  private void scheduleSubtitleUpdate(@NonNull List<Cue> cues, @NonNull String text) {
    if (disposed) return;
    final long delay = Math.max(0, subtitleDelayMs);
    final Runnable task = () -> updateSubtitles(cues, text);
    final Runnable prev = pendingSubtitleUpdate;
    pendingSubtitleUpdate = task;
    if (prev != null) {
      mainHandler.removeCallbacks(prev);
    }
    if (delay <= 0) {
      mainHandler.post(task);
    } else {
      mainHandler.postDelayed(task, delay);
    }
  }

  private void updateSubtitles(@NonNull List<Cue> cues, @NonNull String text) {
    if (disposed) return;
    subtitleCues = new ArrayList<>(cues);
    subtitleText = text;
    final SubtitleView view = platformSubtitleView;
    if (view == null) return;
    view.setCues(subtitleCues);
    view.setVisibility(subtitleCues.isEmpty() ? View.GONE : View.VISIBLE);
  }

  private void applySubtitleStyle(@NonNull SubtitleView view) {
    final float sizeSp = (float) subtitleFontSize;
    final Typeface typeface = subtitleBold ? Typeface.DEFAULT_BOLD : Typeface.DEFAULT;
    view.setApplyEmbeddedStyles(true);
    view.setApplyEmbeddedFontSizes(true);
    view.setFixedTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp);
    view.setStyle(
        new CaptionStyleCompat(
            Color.WHITE,
            Color.TRANSPARENT,
            Color.TRANSPARENT,
            CaptionStyleCompat.EDGE_TYPE_OUTLINE,
            Color.BLACK,
            typeface));
    view.setBottomPaddingFraction(0f);

    final float density = view.getResources().getDisplayMetrics().density;
    final int left = Math.round(24f * density);
    final int top = Math.round(8f * density);
    final int right = Math.round(24f * density);
    final int bottom = Math.round((float) subtitleBottomPadding * density);
    view.setPadding(left, top, right, bottom);
  }

  @NonNull
  private static Uri toAndroidUri(@NonNull String uriOrPath) {
    final String trimmed = uriOrPath.trim();
    final Uri parsed = Uri.parse(trimmed);
    if (parsed.getScheme() == null || parsed.getScheme().isEmpty()) {
      return Uri.fromFile(new File(trimmed));
    }
    return parsed;
  }

  @Nullable
  private static String guessSubtitleMimeType(@NonNull String uriOrPath) {
    final String lower = uriOrPath.toLowerCase();
    if (lower.endsWith(".srt")) return "application/x-subrip";
    if (lower.endsWith(".vtt")) return "text/vtt";
    if (lower.endsWith(".ass") || lower.endsWith(".ssa")) return "text/x-ssa";
    if (lower.endsWith(".ttml") || lower.endsWith(".xml")) return "application/ttml+xml";
    if (lower.endsWith(".sup") || lower.endsWith(".pgs")) return "application/pgs";
    if (lower.endsWith(".sub")) return "application/vobsub";
    return null;
  }

  @NonNull
  private static String cueGroupToText(@NonNull CueGroup cueGroup) {
    final StringBuilder sb = new StringBuilder();
    for (final Cue cue : cueGroup.cues) {
      if (cue.text == null) {
        continue;
      }
      final String line = cue.text.toString().trim();
      if (line.isEmpty()) {
        continue;
      }
      if (sb.length() > 0) {
        sb.append('\n');
      }
      sb.append(line);
    }
    return sb.toString();
  }

  public void dispose() {
    disposed = true;
    mainHandler.removeCallbacksAndMessages(null);
    exoPlayer.removeListener(subtitleListener);
    platformSubtitleView = null;
    subtitleCues = new ArrayList<>();
    if (disposeHandler != null) {
      disposeHandler.onDispose();
    }
    exoPlayer.release();
  }
}
