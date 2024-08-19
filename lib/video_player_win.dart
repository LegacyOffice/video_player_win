import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'video_player_win_platform_interface.dart';

enum WinDataSourceType { asset, network, file, contentUri }

@immutable
class WinVideoPlayerValue {
  final Duration duration;
  final bool isBuffering;
  final bool isInitialized;
  final bool isLooping;
  final bool isPlaying;
  final bool isCompleted;
  final double playbackSpeed;
  final Duration position;
  final Size size;
  final double volume;
  final String? errorDescription;
  final int textureId; // For internal use only

  bool get hasError => errorDescription != null;

  double get aspectRatio => size.isEmpty ? 1 : size.width / size.height;

  const WinVideoPlayerValue({
    this.textureId = -1,
    this.duration = Duration.zero,
    this.size = Size.zero,
    this.position = Duration.zero,
    this.isInitialized = false,
    this.isPlaying = false,
    this.isLooping = false,
    this.isBuffering = false,
    this.isCompleted = false,
    this.volume = 1.0,
    this.playbackSpeed = 1.0,
    this.errorDescription,
  });

  WinVideoPlayerValue copyWith({
    int? textureId,
    Duration? duration,
    bool? isBuffering,
    bool? isInitialized,
    bool? isLooping,
    bool? isPlaying,
    bool? isCompleted,
    double? playbackSpeed,
    Duration? position,
    Size? size,
    double? volume,
    String? errorDescription,
  }) {
    return WinVideoPlayerValue(
      textureId: textureId ?? this.textureId,
      duration: duration ?? this.duration,
      isBuffering: isBuffering ?? this.isBuffering,
      isInitialized: isInitialized ?? this.isInitialized,
      isLooping: isLooping ?? this.isLooping,
      isPlaying: isPlaying ?? this.isPlaying,
      isCompleted: isCompleted ?? this.isCompleted,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      position: position ?? this.position,
      size: size ?? this.size,
      volume: volume ?? this.volume,
      errorDescription: errorDescription ?? this.errorDescription,
    );
  }
}

class WinVideoPlayerController extends ValueNotifier<WinVideoPlayerValue> {
  late final bool _isBridgeMode; // true if used by 'video_player' package
  int textureId_ = -1;
  final String dataSource;
  late final WinDataSourceType dataSourceType;
  final Map<String, String>? headers; // Add headers field
  bool _isLooping = false;

  // Used by flutter official "video_player" package
  final _eventStreamController = StreamController<VideoEvent>();

  Stream<VideoEvent> get videoEventStream => _eventStreamController.stream;

  Future<Duration?> get position async {
    var pos = await _getCurrentPosition();
    return Duration(milliseconds: pos);
  }

  // Updated constructor to accept headers
  WinVideoPlayerController._(this.dataSource, this.dataSourceType,
      {this.headers, bool isBridgeMode = false})
      : super(WinVideoPlayerValue()) {
    if (dataSourceType == WinDataSourceType.contentUri) {
      throw UnsupportedError(
          "VideoPlayerController.contentUri() not supported in Windows");
    }
    if (dataSourceType == WinDataSourceType.asset) {
      throw UnsupportedError(
          "VideoPlayerController.asset() not implemented yet.");
    }

    _isBridgeMode = isBridgeMode;
  }

  static final Finalizer<int> _finalizer = Finalizer((textureId) {
    log("[video_player_win] GC free a player that didn't dispose() yet!");
    VideoPlayerWinPlatform.instance.unregisterPlayer(textureId);
    VideoPlayerWinPlatform.instance.dispose(textureId);
  });

  WinVideoPlayerController.file(File file, {bool isBridgeMode = false})
      : this._(file.path, WinDataSourceType.file, isBridgeMode: isBridgeMode);

  WinVideoPlayerController.network(String dataSource,
      {Map<String, String>? headers, bool isBridgeMode = false})
      : this._(dataSource, WinDataSourceType.network,
          headers: headers, isBridgeMode: isBridgeMode);

  WinVideoPlayerController.asset(String dataSource, {String? package})
      : this._(dataSource, WinDataSourceType.asset);

  WinVideoPlayerController.contentUri(Uri contentUri)
      : this._("", WinDataSourceType.contentUri);

  Timer? _positionTimer;

  void _cancelTrackingPosition() => _positionTimer?.cancel();

  void _startTrackingPosition() async {
    if (_isBridgeMode) return;

    _positionTimer?.cancel();
    _positionTimer =
        Timer.periodic(const Duration(milliseconds: 300), (Timer timer) async {
      if (!value.isInitialized ||
          !value.isPlaying ||
          value.isCompleted ||
          value.hasError) {
        timer.cancel();
        return;
      }

      await position;
    });
  }

  void onPlaybackEvent_(int state) {
    switch (state) {
      case 1: // MEBufferingStarted
        log("[video_player_win] Playback event: buffering start");
        value = value.copyWith(isInitialized: true, isBuffering: true);
        _eventStreamController
            .add(VideoEvent(eventType: VideoEventType.bufferingStart));
        break;
      case 2: // MEBufferingStopped
        log("[video_player_win] Playback event: buffering finish");
        value = value.copyWith(isInitialized: true, isBuffering: false);
        _eventStreamController
            .add(VideoEvent(eventType: VideoEventType.bufferingEnd));
        break;
      case 3: // MESessionStarted
        value = value.copyWith(
            isInitialized: true, isPlaying: true, isCompleted: false);
        _startTrackingPosition();
        _eventStreamController
            .add(VideoEvent(eventType: VideoEventType.isPlayingStateUpdate));
        break;
      case 4: // MESessionPaused
        value = value.copyWith(isPlaying: false);
        _cancelTrackingPosition();
        _eventStreamController
            .add(VideoEvent(eventType: VideoEventType.isPlayingStateUpdate));
        break;
      case 5: // MESessionStopped
        log("[video_player_win] Playback event: stopped");
        value = value.copyWith(isPlaying: false);
        _cancelTrackingPosition();
        _eventStreamController
            .add(VideoEvent(eventType: VideoEventType.isPlayingStateUpdate));
        break;
      case 6: // MESessionEnded
        if (_isLooping) {
          seekTo(Duration.zero);
        } else {
          _cancelTrackingPosition();
          value = value.copyWith(isCompleted: true, position: value.duration);
          _eventStreamController
              .add(VideoEvent(eventType: VideoEventType.completed));
        }
        break;
      case 7: // MEError
        log("[video_player_win] Playback event: error");
        value = value.copyWith(
            isInitialized: false,
            isPlaying: false,
            duration: Duration.zero,
            errorDescription: "N/A");
        var exp = PlatformException(code: "decode failed", message: "N/A");
        _eventStreamController.addError(exp);
        _cancelTrackingPosition();
        break;
    }
  }

  Future<void> initialize() async {
    if (dataSourceType == WinDataSourceType.network && headers != null) {
      WinVideoPlayerValue? pv = await VideoPlayerWinPlatform.instance
          .openVideo(this, textureId_, dataSource, headers: headers);
      if (pv == null) {
        log("[video_player_win] Controller initialize (open video) failed");
        value = value.copyWith(
            isInitialized: false, errorDescription: "open file failed");
        _eventStreamController.add(VideoEvent(
            eventType: VideoEventType.initialized, duration: null, size: null));
        return;
      }
      textureId_ = pv.textureId;
      value = pv;
      _finalizer.attach(this, textureId_, detach: this);

      _eventStreamController.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: pv.duration,
        size: pv.size,
      ));
      log("flutter: video player file opened: id=$textureId_");
    } else {
      WinVideoPlayerValue? pv = await VideoPlayerWinPlatform.instance
          .openVideo(this, textureId_, dataSource);
      if (pv == null) {
        log("[video_player_win] Controller initialize (open video) failed");
        value = value.copyWith(
            isInitialized: false, errorDescription: "open file failed");
        _eventStreamController.add(VideoEvent(
            eventType: VideoEventType.initialized, duration: null, size: null));
        return;
      }
      textureId_ = pv.textureId;
      value = pv;
      _finalizer.attach(this, textureId_, detach: this);

      _eventStreamController.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: pv.duration,
        size: pv.size,
      ));
      log("flutter: video player file opened: id=$textureId_");
    }
  }

  Future<void> play() async {
    if (!value.isInitialized) throw ArgumentError("Video file not opened yet");
    await VideoPlayerWinPlatform.instance.play(textureId_);
  }

  Future<void> pause() async {
    if (!value.isInitialized) throw ArgumentError("Video file not opened yet");
    await VideoPlayerWinPlatform.instance.pause(textureId_);
  }

  Future<void> seekTo(Duration time) async {
    if (!value.isInitialized) throw ArgumentError("Video file not opened yet");

    await VideoPlayerWinPlatform.instance
        .seekTo(textureId_, time.inMilliseconds);
    value = value.copyWith(position: time, isCompleted: false);
  }

  Future<int> _getCurrentPosition() async {
    if (!value.isInitialized) throw ArgumentError("Video file not opened yet");
    if (value.isCompleted) return value.duration.inMilliseconds;
    int pos =
        await VideoPlayerWinPlatform.instance.getCurrentPosition(textureId_);

    if (textureId_ < 0) return 0;
    value = value.copyWith(position: Duration(milliseconds: pos));
    return pos;
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (!value.isInitialized) throw ArgumentError("Video file not opened yet");
    await VideoPlayerWinPlatform.instance.setPlaybackSpeed(textureId_, speed);
    value = value.copyWith(playbackSpeed: speed);
  }

  Future<void> setVolume(double volume) async {
    if (!value.isInitialized) throw ArgumentError("Video file not opened yet");
    await VideoPlayerWinPlatform.instance.setVolume(textureId_, volume);
    value = value.copyWith(volume: volume);
  }

  Future<void> setLooping(bool looping) async {
    _isLooping = looping;
    value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> dispose() async {
    VideoPlayerWinPlatform.instance.unregisterPlayer(textureId_);
    await VideoPlayerWinPlatform.instance.dispose(textureId_);

    _finalizer.detach(this);
    _cancelTrackingPosition();

    textureId_ = -1;
    value = value.copyWith(textureId: -1);
    super.dispose();

    log("flutter: video player dispose: id=$textureId_");
  }
}

class WinVideoPlayer extends StatelessWidget {
  final WinVideoPlayerController controller;
  final FilterQuality filterQuality;

  const WinVideoPlayer(this.controller,
      {Key? key, this.filterQuality = FilterQuality.low})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Texture(
          textureId: controller.textureId_,
          filterQuality: filterQuality,
        ),
      ),
    );
  }
}
