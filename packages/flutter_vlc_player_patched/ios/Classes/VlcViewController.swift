import Darwin
import Flutter
import Foundation
import MobileVLCKit
import UIKit

private protocol VLCPlayerHostedViewDelegate: AnyObject {
    func hostedViewReadinessDidChange(_ hostedView: VLCPlayerHostedView)
}

final class VLCPlayerHostedView: UIView {
    fileprivate weak var readinessDelegate: VLCPlayerHostedViewDelegate?

    weak var player: VLCMediaPlayer? {
        didSet {
            attachDrawableIfNeeded(forceRebind: true)
            notifyReadinessDelegate()
        }
    }

    var isReadyForPlayback: Bool {
        window != nil && bounds.width > 0 && bounds.height > 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachDrawableIfNeeded()
        notifyReadinessDelegate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachDrawableIfNeeded(forceRebind: true)
        notifyReadinessDelegate()
    }

    func attachDrawableIfNeeded(forceRebind: Bool = false) {
        guard let player = player else {
            return
        }
        guard window != nil else {
            player.drawable = nil
            return
        }
        if forceRebind {
            player.drawable = nil
        }
        if !forceRebind, let drawable = player.drawable as? UIView, drawable === self {
            return
        }
        player.drawable = self
    }

    private func notifyReadinessDelegate() {
        readinessDelegate?.hostedViewReadinessDidChange(self)
    }
}

public class VLCViewController: NSObject, FlutterPlatformView, VLCPlayerHostedViewDelegate {
    private let hostedView: VLCPlayerHostedView
    private let vlcMediaPlayer: VLCMediaPlayer
    private let mediaEventChannel: FlutterEventChannel
    private let mediaEventChannelHandler: VLCPlayerEventStreamHandler
    private let rendererEventChannel: FlutterEventChannel
    private let rendererEventChannelHandler: VLCRendererEventStreamHandler
    private var rendererDiscoverers: [VLCRendererDiscoverer] = []

    private var mediaOptions: [String] = []
    private var loopingEnabled = false
    private var pendingSeekPosition: Int64?
    private var requestedVolume: Int32
    private var requestedPlaybackSpeed: Float
    private var requestedVideoScale: Float
    private var requestedAspectRatio: String?
    private var aspectRatioCString: UnsafeMutablePointer<Int8>?
    private var pendingAutoPlay = false
    private var startupRecoveryAttempted = false
    private var startupValidationWorkItem: DispatchWorkItem?
    private var lastKnownVideoSize = CGSize.zero
    private var lastKnownState: VLCMediaPlayerState = .stopped
    private var lastRuntimeErrorSignature: String?
    private var isDisposed = false

    public func view() -> UIView {
        refreshDrawableBinding()
        return hostedView
    }

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        mediaEventChannel = FlutterEventChannel(
            name: "flutter_video_plugin/getVideoEvents_\(viewId)",
            binaryMessenger: messenger
        )
        rendererEventChannel = FlutterEventChannel(
            name: "flutter_video_plugin/getRendererEvents_\(viewId)",
            binaryMessenger: messenger
        )

        let hostedView = VLCPlayerHostedView(frame: frame)
        hostedView.backgroundColor = .black
        hostedView.clipsToBounds = true
        self.hostedView = hostedView

        let mediaPlayer = VLCMediaPlayer()
        vlcMediaPlayer = mediaPlayer
        requestedVolume = mediaPlayer.audio?.volume ?? 100
        requestedPlaybackSpeed = mediaPlayer.rate > 0 ? mediaPlayer.rate : 1.0
        requestedVideoScale = mediaPlayer.scaleFactor

        mediaEventChannelHandler = VLCPlayerEventStreamHandler()
        rendererEventChannelHandler = VLCRendererEventStreamHandler()

        super.init()

        mediaEventChannelHandler.owner = self
        mediaEventChannel.setStreamHandler(mediaEventChannelHandler)
        rendererEventChannel.setStreamHandler(rendererEventChannelHandler)

        hostedView.readinessDelegate = self
        hostedView.player = mediaPlayer
        mediaPlayer.delegate = mediaEventChannelHandler

        registerLifecycleObservers()
    }

    public func play() {
        guard !isDisposed else {
            return
        }
        pendingAutoPlay = true
        mediaEventChannelHandler.emitOpeningEvent()
        startPlaybackIfReady(reason: "play")
    }

    public func pause() {
        guard !isDisposed else {
            return
        }
        pendingAutoPlay = false
        cancelStartupValidation()
        vlcMediaPlayer.pause()
    }

    public func stop() {
        guard !isDisposed else {
            return
        }
        pendingAutoPlay = false
        pendingSeekPosition = nil
        cancelStartupValidation()
        vlcMediaPlayer.stop()
    }

    public var isPlaying: Bool {
        vlcMediaPlayer.isPlaying
    }

    public var isSeekable: Bool {
        vlcMediaPlayer.isSeekable
    }

    public func setMediaOptions(_ options: [String]) {
        mediaOptions = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func setLooping(isLooping: Bool) {
        loopingEnabled = isLooping
        guard let media = vlcMediaPlayer.media else {
            return
        }
        applyLoopingOption(to: media)
    }

    public func seek(position: Int64) {
        guard !isDisposed else {
            return
        }
        let shouldDeferSeek = vlcMediaPlayer.media == nil || vlcMediaPlayer.state == .stopped
        pendingSeekPosition = shouldDeferSeek ? position : nil
        vlcMediaPlayer.time = VLCTime(number: NSNumber(value: position))
        if shouldDeferSeek {
            schedulePendingSeekReapply()
        }
    }

    public var position: Int64 {
        vlcMediaPlayer.time.value?.int64Value ?? 0
    }

    public var duration: Int64 {
        vlcMediaPlayer.media?.length.value?.int64Value ?? 0
    }

    public func setVolume(volume: Int64) {
        requestedVolume = Int32(truncatingIfNeeded: volume)
        vlcMediaPlayer.audio?.volume = requestedVolume
    }

    public var volume: Int32 {
        vlcMediaPlayer.audio?.volume ?? requestedVolume
    }

    public func setPlaybackSpeed(speed: Float) {
        requestedPlaybackSpeed = speed > 0 ? speed : 1.0
        applyPlaybackSpeedIfNeeded()
    }

    public var playbackSpeed: Float {
        requestedPlaybackSpeed
    }

    public func takeSnapshot() -> String? {
        guard !isDisposed else {
            return nil
        }
        let targetView = (vlcMediaPlayer.drawable as? UIView) ?? hostedView
        let bounds = targetView.bounds.integral
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { _ in
            targetView.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        return image.pngData()?.base64EncodedString()
    }

    public var spuTracksCount: Int32 {
        vlcMediaPlayer.numberOfSubtitlesTracks
    }

    public var spuTracks: [Int: String] {
        vlcMediaPlayer.subtitles()
    }

    public func setSpuTrack(spuTrackNumber: Int32) {
        vlcMediaPlayer.currentVideoSubTitleIndex = spuTrackNumber
    }

    public var spuTrack: Int32 {
        vlcMediaPlayer.currentVideoSubTitleIndex
    }

    public func setSpuDelay(delay: Int) {
        vlcMediaPlayer.currentVideoSubTitleDelay = delay
    }

    public var spuDelay: Int {
        vlcMediaPlayer.currentVideoSubTitleDelay
    }

    public func addSubtitleTrack(uri: String, type: DataSourceType, isSelected: Bool) {
        guard let url = resolvedMediaURL(from: uri, sourceType: type) else {
            return
        }
        vlcMediaPlayer.addPlaybackSlave(
            url,
            type: VLCMediaPlaybackSlaveType.subtitle,
            enforce: isSelected
        )
    }

    public var audioTracksCount: Int32 {
        vlcMediaPlayer.numberOfAudioTracks
    }

    public var audioTracks: [Int: String] {
        vlcMediaPlayer.audioTracks()
    }

    public func setAudioTrack(audioTrackNumber: Int32) {
        vlcMediaPlayer.currentAudioTrackIndex = audioTrackNumber
    }

    public var audioTrack: Int32 {
        vlcMediaPlayer.currentAudioTrackIndex
    }

    public func setAudioDelay(delay: Int) {
        vlcMediaPlayer.currentAudioPlaybackDelay = delay
    }

    public var audioDelay: Int {
        vlcMediaPlayer.currentAudioPlaybackDelay
    }

    public func addAudioTrack(uri: String, type: DataSourceType, isSelected: Bool) {
        guard let url = resolvedMediaURL(from: uri, sourceType: type) else {
            return
        }
        vlcMediaPlayer.addPlaybackSlave(
            url,
            type: VLCMediaPlaybackSlaveType.audio,
            enforce: isSelected
        )
    }

    public var videoTracksCount: Int32 {
        vlcMediaPlayer.numberOfVideoTracks
    }

    public var videoTracks: [Int: String] {
        vlcMediaPlayer.videoTracks()
    }

    public func setVideoTrack(videoTrackNumber: Int32) {
        vlcMediaPlayer.currentVideoTrackIndex = videoTrackNumber
    }

    public var videoTrack: Int32 {
        vlcMediaPlayer.currentVideoTrackIndex
    }

    public func setVideoScale(scale: Float) {
        requestedVideoScale = scale
        vlcMediaPlayer.scaleFactor = scale
    }

    public var videoScale: Float {
        requestedVideoScale
    }

    public func setVideoAspectRatio(aspectRatio: String) {
        let normalized = aspectRatio.trimmingCharacters(in: .whitespacesAndNewlines)
        requestedAspectRatio = normalized.isEmpty ? nil : normalized
        applyAspectRatio()
    }

    public var videoAspectRatio: String {
        if let requestedAspectRatio, !requestedAspectRatio.isEmpty {
            return requestedAspectRatio
        }
        guard let aspectRatio = vlcMediaPlayer.videoAspectRatio else {
            return "1"
        }
        return String(cString: aspectRatio)
    }

    public var availableRendererServices: [String] {
        vlcMediaPlayer.rendererServices()
    }

    public func startRendererScanning() {
        stopRendererScanning()
        for rendererService in vlcMediaPlayer.rendererServices() {
            guard let rendererDiscoverer = VLCRendererDiscoverer(name: rendererService) else {
                continue
            }
            rendererDiscoverer.delegate = rendererEventChannelHandler
            rendererDiscoverer.start()
            rendererDiscoverers.append(rendererDiscoverer)
        }
    }

    public func stopRendererScanning() {
        for rendererDiscoverer in rendererDiscoverers {
            rendererDiscoverer.stop()
            rendererDiscoverer.delegate = nil
        }
        rendererDiscoverers.removeAll()
        rendererEventChannelHandler.renderItems.removeAll()
        if vlcMediaPlayer.isPlaying {
            vlcMediaPlayer.pause()
        }
        vlcMediaPlayer.setRendererItem(nil)
    }

    public var rendererDevices: [String: String] {
        var rendererDevices: [String: String] = [:]
        for item in rendererEventChannelHandler.renderItems {
            rendererDevices[item.name] = item.name
        }
        return rendererDevices
    }

    public func cast(rendererDevice: String) {
        if vlcMediaPlayer.isPlaying {
            vlcMediaPlayer.pause()
        }
        let rendererItem = rendererEventChannelHandler.renderItems.first { $0.name == rendererDevice }
        vlcMediaPlayer.setRendererItem(rendererItem)
        vlcMediaPlayer.play()
    }

    public func startRecording(saveDirectory: String) -> Bool {
        vlcMediaPlayer.startRecording(atPath: saveDirectory)
    }

    public func stopRecording() -> Bool {
        vlcMediaPlayer.stopRecording()
    }

    public func dispose() {
        guard !isDisposed else {
            return
        }
        isDisposed = true
        NotificationCenter.default.removeObserver(self)
        stopRendererScanning()
        mediaEventChannel.setStreamHandler(nil)
        rendererEventChannel.setStreamHandler(nil)
        cancelStartupValidation()
        vlcMediaPlayer.stop()
        vlcMediaPlayer.delegate = nil
        vlcMediaPlayer.drawable = nil
        vlcMediaPlayer.media = nil
        hostedView.player = nil
        if let aspectRatioCString {
            free(aspectRatioCString)
            self.aspectRatioCString = nil
        }
        pendingSeekPosition = nil
    }

    func setMediaPlayerUrl(
        uri: String,
        sourceType: DataSourceType,
        autoPlay: Bool,
        hwAcc: Int
    ) {
        guard !isDisposed else {
            return
        }

        stopRendererScanning()
        cancelStartupValidation()
        resetStartupDiagnostics()
        pendingAutoPlay = autoPlay
        pendingSeekPosition = nil
        vlcMediaPlayer.stop()
        vlcMediaPlayer.media = nil

        guard let media = makeMedia(uri: uri, sourceType: sourceType) else {
            return
        }

        media.delegate = mediaEventChannelHandler
        applyMediaOptions(to: media, hwAcc: hwAcc)

        vlcMediaPlayer.media = media
        refreshDrawableBinding(forceRebind: true)
        applyPersistentPlayerState(allowDeferredPlaybackSpeed: false)

        if autoPlay {
            DispatchQueue.main.async { [weak self] in
                self?.mediaEventChannelHandler.emitOpeningEvent()
                self?.startPlaybackIfReady(reason: "set-media")
            }
        }
    }

    func handleMediaPlayerStateChanged(_ player: VLCMediaPlayer?) {
        guard !isDisposed, player === vlcMediaPlayer else {
            return
        }
        lastKnownState = player?.state ?? .stopped
        noteVideoOutput(player?.videoSize ?? .zero)
        switch player?.state {
        case .opening, .buffering, .playing:
            applyPendingSeekIfNeeded()
            scheduleStartupValidation(reason: "state-\(describeState(player?.state))")
        case .paused, .stopped, .ended:
            cancelStartupValidation()
        case .error:
            cancelStartupValidation()
            emitRuntimeError(
                code: "vlc_state_error",
                message: "iOS VLC entered an error state.",
                additionalDetails: [
                    "reason": "media-player-state-error",
                ]
            )
        default:
            break
        }
        if player?.state == .playing {
            applyPlaybackSpeedIfNeeded()
        }
    }

    func handleMediaPlayerTimeChanged(_ position: Int64) {
        noteVideoOutput(vlcMediaPlayer.videoSize)
        if hasKnownVideoOutput {
            cancelStartupValidation()
        }
        guard let pendingSeekPosition else {
            return
        }
        if abs(position - pendingSeekPosition) <= 1500 {
            self.pendingSeekPosition = nil
        }
    }

    func hostedViewReadinessDidChange(_ hostedView: VLCPlayerHostedView) {
        guard !isDisposed else {
            return
        }
        if hostedView.isReadyForPlayback {
            refreshDrawableBinding(forceRebind: true)
            if pendingAutoPlay {
                startPlaybackIfReady(reason: "surface-ready")
            }
            if vlcMediaPlayer.isPlaying {
                scheduleStartupValidation(reason: "surface-rebound")
            }
        }
    }

    private func registerLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    private func makeMedia(uri: String, sourceType: DataSourceType) -> VLCMedia? {
        let trimmedUri = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUri.isEmpty else {
            return nil
        }

        switch sourceType {
        case .ASSET:
            return VLCMedia(path: trimmedUri)
        case .FILE:
            guard let fileURL = resolvedMediaURL(from: trimmedUri, sourceType: sourceType) else {
                return nil
            }
            return VLCMedia(url: fileURL)
        case .NETWORK:
            guard let url = resolvedMediaURL(from: trimmedUri, sourceType: sourceType) else {
                return nil
            }
            return url.isFileURL ? VLCMedia(url: url) : VLCMedia(url: url)
        }
    }

    private func resolvedMediaURL(from uri: String, sourceType: DataSourceType) -> URL? {
        let trimmedUri = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUri.isEmpty else {
            return nil
        }

        switch sourceType {
        case .ASSET:
            return URL(fileURLWithPath: trimmedUri)
        case .FILE:
            if let url = URL(string: trimmedUri), url.isFileURL {
                return url
            }
            let expandedPath = NSString(string: trimmedUri).expandingTildeInPath
            return URL(fileURLWithPath: expandedPath)
        case .NETWORK:
            if let url = URL(string: trimmedUri) {
                return url
            }
            guard let encoded = trimmedUri.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) else {
                return nil
            }
            return URL(string: encoded)
        }
    }

    private func applyMediaOptions(to media: VLCMedia, hwAcc: Int) {
        for option in mediaOptions {
            media.addOption(option)
        }
        applyLoopingOption(to: media)

        switch HWAccellerationType(rawValue: hwAcc) {
        case .HW_ACCELERATION_DISABLED:
            media.addOption("--codec=avcodec")
        case .HW_ACCELERATION_DECODING:
            media.addOption("--codec=all")
            media.addOption(":no-mediacodec-dr")
            media.addOption(":no-omxil-dr")
        case .HW_ACCELERATION_FULL:
            media.addOption("--codec=all")
        case .HW_ACCELERATION_AUTOMATIC, .none:
            break
        }
    }

    private func applyLoopingOption(to media: VLCMedia) {
        media.addOption(loopingEnabled ? "--loop" : "--no-loop")
    }

    private func applyPersistentPlayerState(allowDeferredPlaybackSpeed: Bool) {
        vlcMediaPlayer.audio?.volume = requestedVolume
        vlcMediaPlayer.scaleFactor = requestedVideoScale
        applyAspectRatio()
        if allowDeferredPlaybackSpeed {
            applyPlaybackSpeedIfNeeded()
        }
    }

    private func applyAspectRatio() {
        if let aspectRatioCString {
            free(aspectRatioCString)
            self.aspectRatioCString = nil
        }
        guard let requestedAspectRatio, !requestedAspectRatio.isEmpty else {
            vlcMediaPlayer.videoAspectRatio = nil
            return
        }
        aspectRatioCString = strdup(requestedAspectRatio)
        vlcMediaPlayer.videoAspectRatio = aspectRatioCString
    }

    private func applyPlaybackSpeedIfNeeded() {
        guard !isDisposed, requestedPlaybackSpeed > 0 else {
            return
        }
        guard vlcMediaPlayer.isPlaying else {
            return
        }
        vlcMediaPlayer.rate = requestedPlaybackSpeed
    }

    private func applyPendingSeekIfNeeded() {
        guard let pendingSeekPosition else {
            return
        }
        vlcMediaPlayer.time = VLCTime(number: NSNumber(value: pendingSeekPosition))
    }

    private var isHostedViewReadyForPlayback: Bool {
        hostedView.isReadyForPlayback
    }

    private var hasKnownVideoOutput: Bool {
        lastKnownVideoSize.width > 0 && lastKnownVideoSize.height > 0
    }

    private func noteVideoOutput(_ size: CGSize) {
        if size.width > 0, size.height > 0 {
            lastKnownVideoSize = size
            lastRuntimeErrorSignature = nil
        }
    }

    private func resetStartupDiagnostics() {
        lastKnownVideoSize = .zero
        lastKnownState = .stopped
        startupRecoveryAttempted = false
        lastRuntimeErrorSignature = nil
    }

    private func schedulePendingSeekReapply() {
        guard pendingSeekPosition != nil else {
            return
        }
        scheduleOnMain(delay: 0.1) { [weak self] in
            self?.applyPendingSeekIfNeeded()
        }
        scheduleOnMain(delay: 0.3) { [weak self] in
            self?.applyPendingSeekIfNeeded()
        }
    }

    private func schedulePlaybackSpeedApply() {
        scheduleOnMain(delay: 0.0) { [weak self] in
            self?.applyPlaybackSpeedIfNeeded()
        }
        scheduleOnMain(delay: 0.1) { [weak self] in
            self?.applyPlaybackSpeedIfNeeded()
        }
    }

    private func startPlaybackIfReady(reason: String) {
        guard !isDisposed else {
            return
        }
        refreshDrawableBinding(forceRebind: true)
        guard vlcMediaPlayer.media != nil else {
            return
        }
        guard isHostedViewReadyForPlayback else {
            return
        }

        startupRecoveryAttempted = false
        pendingAutoPlay = false
        applyPendingSeekIfNeeded()
        vlcMediaPlayer.play()
        schedulePendingSeekReapply()
        schedulePlaybackSpeedApply()
        refreshDrawableBinding()
        scheduleStartupValidation(reason: reason)
    }

    private func refreshDrawableBinding(forceRebind: Bool = false) {
        guard !isDisposed else {
            return
        }
        scheduleOnMain(delay: 0.0) { [weak self] in
            self?.hostedView.attachDrawableIfNeeded(forceRebind: forceRebind)
        }
        scheduleOnMain(delay: 0.1) { [weak self] in
            self?.hostedView.attachDrawableIfNeeded(forceRebind: false)
        }
        scheduleOnMain(delay: 0.3) { [weak self] in
            self?.hostedView.attachDrawableIfNeeded(forceRebind: false)
        }
    }

    private func cancelStartupValidation() {
        startupValidationWorkItem?.cancel()
        startupValidationWorkItem = nil
    }

    private func scheduleStartupValidation(reason: String) {
        guard !isDisposed, vlcMediaPlayer.media != nil else {
            return
        }
        guard isHostedViewReadyForPlayback else {
            return
        }
        cancelStartupValidation()
        let workItem = DispatchWorkItem { [weak self] in
            self?.validateStartupState(reason: reason)
        }
        startupValidationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    private func validateStartupState(reason: String) {
        guard !isDisposed, vlcMediaPlayer.media != nil else {
            return
        }
        guard isHostedViewReadyForPlayback else {
            return
        }

        noteVideoOutput(vlcMediaPlayer.videoSize)
        if hasKnownVideoOutput {
            cancelStartupValidation()
            return
        }

        switch vlcMediaPlayer.state {
        case .opening, .buffering, .playing:
            break
        default:
            return
        }

        if !startupRecoveryAttempted {
            startupRecoveryAttempted = true
            refreshDrawableBinding(forceRebind: true)
            if !vlcMediaPlayer.isPlaying {
                vlcMediaPlayer.play()
            }
            schedulePendingSeekReapply()
            schedulePlaybackSpeedApply()
            scheduleStartupValidation(reason: "native-rebind")
            return
        }

        emitRuntimeError(
            code: "vlc_startup_black_screen",
            message: "iOS VLC started but did not produce video output.",
            additionalDetails: [
                "reason": reason,
            ]
        )
    }

    private func emitRuntimeError(
        code: String,
        message: String,
        additionalDetails: [String: Any] = [:]
    ) {
        var details: [String: Any] = [
            "state": describeState(lastKnownState),
            "positionMs": vlcMediaPlayer.time.value?.int64Value ?? 0,
            "durationMs": vlcMediaPlayer.media?.length.value?.int64Value ?? 0,
            "videoWidth": Int64(lastKnownVideoSize.width.rounded()),
            "videoHeight": Int64(lastKnownVideoSize.height.rounded()),
            "viewReady": isHostedViewReadyForPlayback,
            "drawableBound": vlcMediaPlayer.drawable != nil,
        ]
        for (key, value) in additionalDetails {
            details[key] = value
        }
        let signature = "\(code)|\(message)|\(details["state"] ?? "")|\(details["reason"] ?? "")"
        if lastRuntimeErrorSignature == signature {
            return
        }
        lastRuntimeErrorSignature = signature
        mediaEventChannelHandler.emitError(code: code, message: message, details: details)
    }

    private func describeState(_ state: VLCMediaPlayerState?) -> String {
        switch state {
        case .opening:
            return "opening"
        case .buffering:
            return "buffering"
        case .playing:
            return "playing"
        case .paused:
            return "paused"
        case .stopped:
            return "stopped"
        case .ended:
            return "ended"
        case .error:
            return "error"
        case .esAdded:
            return "esAdded"
        case .none:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }

    private func scheduleOnMain(delay: TimeInterval, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isDisposed else {
                return
            }
            action()
        }
    }

    @objc private func handleApplicationDidBecomeActive() {
        refreshDrawableBinding(forceRebind: true)
        applyPersistentPlayerState(allowDeferredPlaybackSpeed: true)
        if pendingAutoPlay || vlcMediaPlayer.isPlaying {
            scheduleStartupValidation(reason: "app-did-become-active")
        }
    }

    @objc private func handleApplicationWillEnterForeground() {
        refreshDrawableBinding(forceRebind: true)
        applyPersistentPlayerState(allowDeferredPlaybackSpeed: true)
        if pendingAutoPlay {
            startPlaybackIfReady(reason: "app-will-enter-foreground")
        } else if vlcMediaPlayer.isPlaying {
            scheduleStartupValidation(reason: "app-will-enter-foreground")
        }
    }

    @objc private func handleApplicationDidEnterBackground() {
        cancelStartupValidation()
        vlcMediaPlayer.drawable = nil
    }
}

final class VLCRendererEventStreamHandler: NSObject, FlutterStreamHandler, VLCRendererDiscovererDelegate {
    private var rendererEventSink: FlutterEventSink?
    var renderItems: [VLCRendererItem] = []

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        rendererEventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        rendererEventSink = nil
        return nil
    }

    func rendererDiscovererItemAdded(_ rendererDiscoverer: VLCRendererDiscoverer, item: VLCRendererItem) {
        renderItems.append(item)
        rendererEventSink?([
            "event": "attached",
            "id": item.name,
            "name": item.name,
        ])
    }

    func rendererDiscovererItemDeleted(_ rendererDiscoverer: VLCRendererDiscoverer, item: VLCRendererItem) {
        if let index = renderItems.firstIndex(of: item) {
            renderItems.remove(at: index)
        }
        rendererEventSink?([
            "event": "detached",
            "id": item.name,
            "name": item.name,
        ])
    }
}

final class VLCPlayerEventStreamHandler: NSObject, FlutterStreamHandler, VLCMediaPlayerDelegate, VLCMediaDelegate {
    weak var owner: VLCViewController?
    private var mediaEventSink: FlutterEventSink?

    func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        mediaEventSink = events
        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        mediaEventSink = nil
        return nil
    }

    func emitOpeningEvent() {
        mediaEventSink?([
            "event": "opening",
        ])
    }

    func emitError(code: String, message: String, details: [String: Any]) {
        mediaEventSink?(FlutterError(code: code, message: message, details: details))
    }

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else {
            return
        }
        owner?.handleMediaPlayerStateChanged(player)
        guard let mediaEventSink else {
            return
        }

        switch player.state {
        case .opening:
            mediaEventSink([
                "event": "opening",
            ])
        case .paused:
            mediaEventSink([
                "event": "paused",
            ])
        case .stopped:
            mediaEventSink([
                "event": "stopped",
            ])
        case .playing:
            mediaEventSink(eventPayload(event: "playing", player: player))
        case .ended:
            mediaEventSink([
                "event": "ended",
                "position": player.time.value?.int64Value ?? 0,
            ])
        case .buffering:
            mediaEventSink(eventPayload(event: "buffering", player: player))
        case .error:
            break
        case .esAdded:
            break
        @unknown default:
            break
        }
    }

    func mediaPlayerStartedRecording(_ player: VLCMediaPlayer) {
        mediaEventSink?([
            "event": "recording",
            "isRecording": true,
            "recordPath": "",
        ])
    }

    func mediaPlayer(_ player: VLCMediaPlayer, recordingStoppedAtPath path: String) {
        mediaEventSink?([
            "event": "recording",
            "isRecording": false,
            "recordPath": path,
        ])
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else {
            return
        }
        let position = player.time.value?.int64Value ?? 0
        owner?.handleMediaPlayerTimeChanged(position)
        mediaEventSink?(eventPayload(event: "timeChanged", player: player))
    }

    private func eventPayload(event: String, player: VLCMediaPlayer) -> [String: Any] {
        [
            "event": event,
            "height": Int64(player.videoSize.height),
            "width": Int64(player.videoSize.width),
            "speed": Double(player.rate),
            "duration": player.media?.length.value?.int64Value ?? 0,
            "position": player.time.value?.int64Value ?? 0,
            "buffer": 100.0,
            "audioTracksCount": Int64(player.numberOfAudioTracks),
            "activeAudioTrack": Int64(player.currentAudioTrackIndex),
            "spuTracksCount": Int64(player.numberOfSubtitlesTracks),
            "activeSpuTrack": Int64(player.currentVideoSubTitleIndex),
            "isPlaying": player.isPlaying,
        ]
    }
}

public enum DataSourceType: Int {
    case ASSET = 0
    case NETWORK = 1
    case FILE = 2
}

enum HWAccellerationType: Int {
    case HW_ACCELERATION_AUTOMATIC = 0
    case HW_ACCELERATION_DISABLED = 1
    case HW_ACCELERATION_DECODING = 2
    case HW_ACCELERATION_FULL = 3
}

extension VLCMediaPlayer {
    func subtitles() -> [Int: String] {
        guard let indexes = videoSubTitlesIndexes as? [Int],
              let names = videoSubTitlesNames as? [String],
              indexes.count == names.count else {
            return [:]
        }

        var subtitles: [Int: String] = [:]
        for (index, value) in indexes.enumerated() where value >= 0 {
            subtitles[value] = names[index]
        }
        return subtitles
    }

    func audioTracks() -> [Int: String] {
        guard let indexes = audioTrackIndexes as? [Int],
              let names = audioTrackNames as? [String],
              indexes.count == names.count else {
            return [:]
        }

        var audios: [Int: String] = [:]
        for (index, value) in indexes.enumerated() where value >= 0 {
            audios[value] = names[index]
        }
        return audios
    }

    func videoTracks() -> [Int: String] {
        guard let indexes = videoTrackIndexes as? [Int],
              let names = videoTrackNames as? [String],
              indexes.count == names.count else {
            return [:]
        }

        var videos: [Int: String] = [:]
        for (index, value) in indexes.enumerated() where value >= 0 {
            videos[value] = names[index]
        }
        return videos
    }

    func rendererServices() -> [String] {
        let renderers = VLCRendererDiscoverer.list()
        var services: [String] = []
        renderers?.forEach { description in
            services.append(description.name)
        }
        return services
    }
}
