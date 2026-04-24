import Flutter
import Foundation
import MobileVLCKit
import UIKit

final class VLCPlayerHostedView: UIView {
    weak var player: VLCMediaPlayer? {
        didSet {
            attachDrawableIfNeeded(forceRebind: true)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        attachDrawableIfNeeded()
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachDrawableIfNeeded(forceRebind: true)
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
        player.drawable = self
    }
}

public class VLCViewController: NSObject, FlutterPlatformView {
    var hostedView: UIView
    var vlcMediaPlayer: VLCMediaPlayer
    var mediaEventChannel: FlutterEventChannel
    let mediaEventChannelHandler: VLCPlayerEventStreamHandler
    var rendererEventChannel: FlutterEventChannel
    let rendererEventChannelHandler: VLCRendererEventStreamHandler
    var rendererdiscoverers: [VLCRendererDiscoverer] = .init()
    private var isDisposed = false
    
    public func view() -> UIView {
        refreshDrawableBinding()
        return self.hostedView
    }
    
    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        let mediaEventChannel = FlutterEventChannel(
            name: "flutter_video_plugin/getVideoEvents_\(viewId)",
            binaryMessenger: messenger
        )
        let rendererEventChannel = FlutterEventChannel(
            name: "flutter_video_plugin/getRendererEvents_\(viewId)",
            binaryMessenger: messenger
        )
        
        let hostedView = VLCPlayerHostedView(frame: frame)
        hostedView.backgroundColor = .black
        hostedView.clipsToBounds = true
        self.hostedView = hostedView
        self.vlcMediaPlayer = VLCMediaPlayer()
//        self.vlcMediaPlayer.libraryInstance.debugLogging = true
//        self.vlcMediaPlayer.libraryInstance.debugLoggingLevel = 3
        self.mediaEventChannel = mediaEventChannel
        self.mediaEventChannelHandler = VLCPlayerEventStreamHandler()
        self.rendererEventChannel = rendererEventChannel
        self.rendererEventChannelHandler = VLCRendererEventStreamHandler()
        super.init()
        //
        self.mediaEventChannel.setStreamHandler(self.mediaEventChannelHandler)
        self.rendererEventChannel.setStreamHandler(self.rendererEventChannelHandler)
        hostedView.player = self.vlcMediaPlayer
        self.vlcMediaPlayer.delegate = self.mediaEventChannelHandler
        registerLifecycleObservers()
    }
    
    public func play() {
        refreshDrawableBinding(forceRebind: true)
        self.vlcMediaPlayer.play()
        refreshDrawableBinding()
    }
    
    public func pause() {
        self.vlcMediaPlayer.pause()
    }
    
    public func stop() {
        self.vlcMediaPlayer.stop()
    }
    
    public var isPlaying: Bool {
        self.vlcMediaPlayer.isPlaying
    }
    
    public var isSeekable: Bool {
        self.vlcMediaPlayer.isSeekable
    }
    
    public func setLooping(isLooping: Bool) {
        self.vlcMediaPlayer.media?.addOption(isLooping ? "--loop" : "--no-loop")
    }
    
    public func seek(position: Int64) {
        self.vlcMediaPlayer.time = VLCTime(number: position as NSNumber)
    }
    
    public var position: Int32 {
        self.vlcMediaPlayer.time.intValue
    }
    
    public var duration: Int32 {
        self.vlcMediaPlayer.media?.length.intValue ?? 0
    }
    
    public func setVolume(volume: Int64) {
        self.vlcMediaPlayer.audio?.volume = volume.int32
    }
    
    public var volume: Int32 {
        self.vlcMediaPlayer.audio?.volume ?? 100
    }
    
    public func setPlaybackSpeed(speed: Float) {
        self.vlcMediaPlayer.rate = speed
    }
    
    public var playbackSpeed: Float {
        self.vlcMediaPlayer.rate
    }
    
    public func takeSnapshot() -> String? {
        let drawable: UIView = self.vlcMediaPlayer.drawable as! UIView
        let size = drawable.frame.size
        UIGraphicsBeginImageContextWithOptions(size, _: false, _: 0.0)
        let rec = drawable.frame
        drawable.drawHierarchy(in: rec, afterScreenUpdates: false)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        let byteArray = (image ?? UIImage()).pngData()
        //
        return byteArray?.base64EncodedString()
    }
    
    public var spuTracksCount: Int32 {
        return self.vlcMediaPlayer.numberOfSubtitlesTracks
    }
    
    public var spuTracks: [Int: String] {
        self.vlcMediaPlayer.subtitles()
    }
    
    public func setSpuTrack(spuTrackNumber: Int32) {
        self.vlcMediaPlayer.currentVideoSubTitleIndex = spuTrackNumber
    }
    
    public var spuTrack: Int32 {
        self.vlcMediaPlayer.currentVideoSubTitleIndex
    }
    
    public func setSpuDelay(delay: Int) {
        self.vlcMediaPlayer.currentVideoSubTitleDelay = delay
    }
    
    public var spuDelay: Int {
        self.vlcMediaPlayer.currentVideoSubTitleDelay
    }
    
    public func addSubtitleTrack(uri: String, isSelected: Bool) {
        // TODO: check for file type
        guard
            let url = URL(string: uri)
        else {
            return
        }
        
        self.vlcMediaPlayer.addPlaybackSlave(
            url,
            type: VLCMediaPlaybackSlaveType.subtitle,
            enforce: isSelected
        )
    }
    
    public var audioTracksCount: Int32 {
        self.vlcMediaPlayer.numberOfAudioTracks
    }
    
    public var audioTracks: [Int: String] {
        self.vlcMediaPlayer.audioTracks()
    }
    
    public func setAudioTrack(audioTrackNumber: Int32) {
        self.vlcMediaPlayer.currentAudioTrackIndex = audioTrackNumber
    }
    
    public var audioTrack: Int32 {
        self.vlcMediaPlayer.currentAudioTrackIndex
    }
    
    public func setAudioDelay(delay: Int) {
        self.vlcMediaPlayer.currentAudioPlaybackDelay = delay
    }
    
    public var audioDelay: Int {
        self.vlcMediaPlayer.currentAudioPlaybackDelay
    }
    
    public func addAudioTrack(uri: String, isSelected: Bool) {
        // TODO: check for file type
        guard let url = URL(string: uri)
        else {
            return
        }
        self.vlcMediaPlayer.addPlaybackSlave(
            url,
            type: VLCMediaPlaybackSlaveType.audio,
            enforce: isSelected
        )
    }
    
    public var videoTracksCount: Int32 {
        self.vlcMediaPlayer.numberOfVideoTracks
    }
    
    public var videoTracks: [Int: String] {
        self.vlcMediaPlayer.videoTracks()
    }
    
    public func setVideoTrack(videoTrackNumber: Int32) {
        self.vlcMediaPlayer.currentVideoTrackIndex = videoTrackNumber
    }
    
    public var videoTrack: Int32 {
        self.vlcMediaPlayer.currentVideoTrackIndex
    }
    
    public func setVideoScale(scale: Float) {
        self.vlcMediaPlayer.scaleFactor = scale
    }
    
    public var videoScale: Float {
        self.vlcMediaPlayer.scaleFactor
    }
    
    public func setVideoAspectRatio(aspectRatio: String) {
        let aspectRatio = UnsafeMutablePointer<Int8>(
            mutating: (aspectRatio as NSString).utf8String
        )
        self.vlcMediaPlayer.videoAspectRatio = aspectRatio
    }
    
    public var videoAspectRatio: String {
        guard let aspectRatio = self.vlcMediaPlayer.videoAspectRatio else {
            return "1"
        }
        
        return String(cString: aspectRatio)
    }
    
    public var availableRendererServices: [String] {
        self.vlcMediaPlayer.rendererServices()
    }
    
    public func startRendererScanning() {
        self.rendererdiscoverers.removeAll()
        self.rendererEventChannelHandler.renderItems.removeAll()
        // chromecast service name: "Bonjour_renderer"
        let rendererServices = self.vlcMediaPlayer.rendererServices()
        for rendererService in rendererServices {
            guard let rendererDiscoverer
                = VLCRendererDiscoverer(name: rendererService)
            else {
                continue
            }
            rendererDiscoverer.delegate = self.rendererEventChannelHandler
            rendererDiscoverer.start()
            self.rendererdiscoverers.append(rendererDiscoverer)
        }
    }
    
    public func stopRendererScanning() {
        for rendererDiscoverer in self.rendererdiscoverers {
            rendererDiscoverer.stop()
            rendererDiscoverer.delegate = nil
        }
        self.rendererdiscoverers.removeAll()
        self.rendererEventChannelHandler.renderItems.removeAll()
        if self.vlcMediaPlayer.isPlaying {
            self.vlcMediaPlayer.pause()
        }
        self.vlcMediaPlayer.setRendererItem(nil)
    }
    
    public var rendererDevices: [String: String] {
        var rendererDevices: [String: String] = [:]
        let rendererItems = self.rendererEventChannelHandler.renderItems
        for (_, item) in rendererItems.enumerated() {
            rendererDevices[item.name] = item.name
        }
        return rendererDevices
    }
    
    public func cast(rendererDevice: String) {
        if self.vlcMediaPlayer.isPlaying {
            self.vlcMediaPlayer.pause()
        }
        let rendererItems = self.rendererEventChannelHandler.renderItems
        let rendererItem = rendererItems.first {
            $0.name.contains(rendererDevice)
        }
        self.vlcMediaPlayer.setRendererItem(rendererItem)
        self.vlcMediaPlayer.play()
    }
    
    public func startRecording(saveDirectory: String) -> Bool {
        return !self.vlcMediaPlayer.startRecording(atPath: saveDirectory)
    }
    
    public func stopRecording() -> Bool {
        return !self.vlcMediaPlayer.stopRecording()
    }
    
    public func dispose() {
        isDisposed = true
        NotificationCenter.default.removeObserver(self)
        self.mediaEventChannel.setStreamHandler(nil)
        self.rendererEventChannel.setStreamHandler(nil)
        self.rendererdiscoverers.removeAll()
        self.rendererEventChannelHandler.renderItems.removeAll()
        self.vlcMediaPlayer.stop()
        self.vlcMediaPlayer.delegate = nil
        self.vlcMediaPlayer.drawable = nil
        self.vlcMediaPlayer.media = nil
        (self.hostedView as? VLCPlayerHostedView)?.player = nil
    }
    
    func setMediaPlayerUrl(uri: String, isAssetUrl: Bool, autoPlay: Bool, hwAcc: Int, options: [String]) {
        self.vlcMediaPlayer.stop()
        self.vlcMediaPlayer.media = nil
        
        var media: VLCMedia
        if isAssetUrl {
            guard let path = Bundle.main.path(forResource: uri, ofType: nil)
            else {
                return
            }
            media = VLCMedia(path: path)
        }
        else {
            guard let url = URL(string: uri)
            else {
                return
            }
            media = VLCMedia(url: url)
        }
        
        if !options.isEmpty {
            for option in options {
                media.addOption(option)
            }
        }
        
        switch HWAccellerationType(rawValue: hwAcc) {
        case .HW_ACCELERATION_DISABLED:
            media.addOption("--codec=avcodec")

        case .HW_ACCELERATION_DECODING:
            media.addOption("--codec=all")
            media.addOption(":no-mediacodec-dr")
            media.addOption(":no-omxil-dr")

        case .HW_ACCELERATION_FULL:
            media.addOption("--codec=all")

        case .HW_ACCELERATION_AUTOMATIC:
            break

        case .none:
            break
        }
        
        self.vlcMediaPlayer.media = media
        refreshDrawableBinding(forceRebind: true)
//        self.vlcMediaPlayer.media.parse(withOptions: VLCMediaParsingOptions(VLCMediaParseLocal | VLCMediaFetchLocal | VLCMediaParseNetwork | VLCMediaFetchNetwork))
        self.vlcMediaPlayer.play()
        refreshDrawableBinding()
        if !autoPlay {
            self.vlcMediaPlayer.stop()
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
    }

    private func refreshDrawableBinding(forceRebind: Bool = false) {
        guard !isDisposed else {
            return
        }
        scheduleDrawableBinding(forceRebind: forceRebind, delay: 0.0)
        scheduleDrawableBinding(forceRebind: false, delay: 0.1)
        scheduleDrawableBinding(forceRebind: false, delay: 0.3)
    }

    private func scheduleDrawableBinding(forceRebind: Bool, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.isDisposed else {
                return
            }
            (self.hostedView as? VLCPlayerHostedView)?
                .attachDrawableIfNeeded(forceRebind: forceRebind)
        }
    }

    @objc private func handleApplicationDidBecomeActive() {
        refreshDrawableBinding(forceRebind: true)
    }

    @objc private func handleApplicationWillEnterForeground() {
        refreshDrawableBinding(forceRebind: true)
    }
}

class VLCRendererEventStreamHandler: NSObject, FlutterStreamHandler, VLCRendererDiscovererDelegate {
    private var rendererEventSink: FlutterEventSink?
    var renderItems: [VLCRendererItem] = .init()
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.rendererEventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.rendererEventSink = nil
        return nil
    }
    
    func rendererDiscovererItemAdded(_ rendererDiscoverer: VLCRendererDiscoverer, item: VLCRendererItem) {
        self.renderItems.append(item)
        
        guard let rendererEventSink = self.rendererEventSink else { return }
        rendererEventSink([
            "event": "attached",
            "id": item.name,
            "name": item.name,
        ])
    }
    
    func rendererDiscovererItemDeleted(_ rendererDiscoverer: VLCRendererDiscoverer, item: VLCRendererItem) {
        if let index = renderItems.firstIndex(of: item) {
            self.renderItems.remove(at: index)
        }
        
        guard let rendererEventSink = self.rendererEventSink else { return }
        rendererEventSink([
            "event": "detached",
            "id": item.name,
            "name": item.name,
        ])
    }
}

class VLCPlayerEventStreamHandler: NSObject, FlutterStreamHandler, VLCMediaPlayerDelegate, VLCMediaDelegate {
    private var mediaEventSink: FlutterEventSink?
    
    func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.mediaEventSink = events
        return nil
    }
    
    func onCancel(withArguments _: Any?) -> FlutterError? {
        self.mediaEventSink = nil
        return nil
    }
    
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let mediaEventSink = self.mediaEventSink else { return }
        
        let player = aNotification.object as? VLCMediaPlayer
        let media = player?.media
        let height = player?.videoSize.height ?? 0
        let width = player?.videoSize.width ?? 0
        let audioTracksCount = player?.numberOfAudioTracks ?? 0
        let activeAudioTrack = player?.currentAudioTrackIndex ?? 0
        let spuTracksCount = player?.numberOfSubtitlesTracks ?? 0
        let activeSpuTrack = player?.currentVideoSubTitleIndex ?? 0
        let duration = media?.length.value ?? 0
        let speed = player?.rate ?? 1
        let position = player?.time.value?.intValue ?? 0
        let buffering = 100.0
        let isPlaying = player?.isPlaying ?? false
                
        switch player?.state {
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
            mediaEventSink([
                "event": "playing",
                "height": height,
                "width": width,
                "speed": speed,
                "duration": duration,
                "audioTracksCount": audioTracksCount,
                "activeAudioTrack": activeAudioTrack,
                "spuTracksCount": spuTracksCount,
                "activeSpuTrack": activeSpuTrack,
            ])
            
        case .ended:
            mediaEventSink([
                "event": "ended",
                "position": position,
            ])
            
        case .buffering:
            mediaEventSink([
                "event": "timeChanged",
                "height": height,
                "width": width,
                "speed": speed,
                "duration": duration,
                "position": position,
                "buffer": buffering,
                "audioTracksCount": audioTracksCount,
                "activeAudioTrack": activeAudioTrack,
                "spuTracksCount": spuTracksCount,
                "activeSpuTrack": activeSpuTrack,
                "isPlaying": isPlaying,
            ])
            
        case .error:
            /* mediaEventSink(
             FlutterError(
             code: "500",
             message: "Player State got an error",
             details: nil)
             ) */
            mediaEventSink([
                "event": "error",
            ])
            
        case .esAdded:
            break
            
        default:
            break
        }
    }
    
    func mediaPlayerStartedRecording(_ player: VLCMediaPlayer) {
        guard let mediaEventSink = self.mediaEventSink else { return }
                
        mediaEventSink([
            "event": "recording",
            "isRecording": true,
            "recordPath": "",
        ])
    }
    
    func mediaPlayer(_ player: VLCMediaPlayer, recordingStoppedAtPath path: String) {
        guard let mediaEventSink = self.mediaEventSink else { return }
        
        mediaEventSink([
            "event": "recording",
            "isRecording": false,
            "recordPath": path,
        ])
    }
    
    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        guard let mediaEventSink = self.mediaEventSink else { return }
        
        let player = aNotification.object as? VLCMediaPlayer
        //
        let height = player?.videoSize.height ?? 0
        let width = player?.videoSize.width ?? 0
        let speed = player?.rate ?? 1
        let duration = player?.media?.length.value ?? 0
        let audioTracksCount = player?.numberOfAudioTracks ?? 0
        let activeAudioTrack = player?.currentAudioTrackIndex ?? 0
        let spuTracksCount = player?.numberOfSubtitlesTracks ?? 0
        let activeSpuTrack = player?.currentVideoSubTitleIndex ?? 0
        let buffering = 100.0
        let isPlaying = player?.isPlaying ?? false
        //
        if let position = player?.time.value {
            mediaEventSink([
                "event": "timeChanged",
                "height": height,
                "width": width,
                "speed": speed,
                "duration": duration,
                "position": position,
                "buffer": buffering,
                "audioTracksCount": audioTracksCount,
                "activeAudioTrack": activeAudioTrack,
                "spuTracksCount": spuTracksCount,
                "activeSpuTrack": activeSpuTrack,
                "isPlaying": isPlaying,
            ])
        }
    }
}

enum DataSourceType: Int {
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
        guard let indexs = videoSubTitlesIndexes as? [Int],
              let names = videoSubTitlesNames as? [String],
              indexs.count == names.count
        else {
            return [:]
        }
        
        var subtitles: [Int: String] = [:]
        
        var i = 0
        for index in indexs {
            if index >= 0 {
                let name = names[i]
                subtitles[Int(index)] = name
            }
            i = i + 1
        }
        
        return subtitles
    }
    
    func audioTracks() -> [Int: String] {
        guard let indexs = audioTrackIndexes as? [Int],
              let names = audioTrackNames as? [String],
              indexs.count == names.count
        else {
            return [:]
        }
        
        var audios: [Int: String] = [:]
        
        var i = 0
        for index in indexs {
            if index >= 0 {
                let name = names[i]
                audios[Int(index)] = name
            }
            i = i + 1
        }
        
        return audios
    }
    
    func videoTracks() -> [Int: String] {
        guard let indexs = videoTrackIndexes as? [Int],
              let names = videoTrackNames as? [String],
              indexs.count == names.count
        else {
            return [:]
        }
        
        var videos: [Int: String] = [:]
        
        var i = 0
        for index in indexs {
            if index >= 0 {
                let name = names[i]
                videos[Int(index)] = name
            }
            i = i + 1
        }
        
        return videos
    }
    
    func rendererServices() -> [String] {
        let renderers = VLCRendererDiscoverer.list()
        var services: [String] = []
        
        renderers?.forEach { VLCRendererDiscovererDescription in
            services.append(VLCRendererDiscovererDescription.name)
        }
        return services
    }
}
