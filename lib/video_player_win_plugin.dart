import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'video_player_win.dart';
import 'video_player_win_platform_interface.dart';

class WindowsVideoPlayer extends VideoPlayerPlatform {
  static void registerWith() {
    VideoPlayerPlatform.instance = WindowsVideoPlayer();
  }

  final mControllerMap = <int, WinVideoPlayerController>{};

  @override
  Future<void> init() async {
    // do nothing...
  }

  /// Clears one video.
  @override
  Future<void> dispose(int textureId) async {
    var controller =
        VideoPlayerWinPlatform.instance.getPlayerByTextureId(textureId);
    await controller?.dispose();
    mControllerMap.remove(textureId);
  }

  /// Creates an instance of a video player and returns its textureId.
  @override
  Future<int?> create(DataSource dataSource, {Map<String, String>? headers}) async {
    if (dataSource.sourceType == DataSourceType.file) {
      var uri = Uri.parse(dataSource.uri!);
      var controller = WinVideoPlayerController.file(
        File(uri.toFilePath()), 
        isBridgeMode: true
      );
      await controller.initialize();
      if (controller.textureId_ > 0) {
        mControllerMap[controller.textureId_] = controller;
        return controller.textureId_;
      }
      return null;
    } else if (dataSource.sourceType == DataSourceType.network) {
      var controller = WinVideoPlayerController.network(
        dataSource.uri!, 
        headers: headers, // Pass headers as a named argument
        isBridgeMode: true
      );
      await controller.initialize();
      if (controller.textureId_ > 0) {
        mControllerMap[controller.textureId_] = controller;
        return controller.textureId_;
      }
      return null;
    } else {
      throw UnimplementedError(
          'create() has not been implemented for dataSource type [assets] and [contentUri] in Windows OS');
    }
  }

  /// Returns a Stream of [VideoEventType]s.
  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    var player =
        VideoPlayerWinPlatform.instance.getPlayerByTextureId(textureId);
    if (player != null) {
      return player.videoEventStream;
    } else {
      var streamController = StreamController<VideoEvent>();
      streamController.add(VideoEvent(
          eventType: VideoEventType.initialized, duration: null, size: null));
      return streamController.stream;
    }
  }

  /// Sets the looping attribute of the video.
  @override
  Future<void> setLooping(int textureId, bool looping) async {
    var controller =
        VideoPlayerWinPlatform.instance.getPlayerByTextureId(textureId);
    await controller?.setLooping(looping);
  }

  /// Starts the video playback.
  @override
  Future<void> play(int textureId) async {
    var controller =
        VideoPlayerWinPlatform.instance.getPlayerByTextureId(textureId);
    await controller?.play();
  }

  /// Stops the video playback.
  @override
  Future<void> pause(int textureId) async {
    var controller =
        VideoPlayerWinPlatform.instance.getPlayerByTextureId(textureId);
    await controller?.pause();
  }

  /// Sets the volume to a range between 0.0 and 1.0.
  @override
  Future<void> setVolume(int textureId, double volume) async {
    var controller =
        VideoPlayerWinPlatform.instance.getPlayerByTextureId(textureId);
    await controller?.setVolume(volume);
  }

  /// Sets the video position to a [Duration] from the start.
  @override
  Future<void> seekTo(int textureId, Duration position) async {
    var controller =
        VideoPlayerWinPlatform.instance.getPlayerByTextureId(textureId);
    await controller?.seekTo(position);
  }

  /// Sets the playback speed to a [speed] value indicating the playback rate.
  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {
    var controller =
        VideoPlayerWinPlatform.instance.getPlayerByTextureId(textureId);
    await controller?.setPlaybackSpeed(speed);
  }

  /// Gets the video position as [Duration] from the start.
  @override
  Future<Duration> getPosition(int textureId) async {
    var controller =
        VideoPlayerWinPlatform.instance.getPlayerByTextureId(textureId);
    return await controller?.position ?? const Duration();
  }

  /// Returns a widget displaying the video with a given textureID.
  @override
  Widget buildView(int textureId) {
    var controller =
        VideoPlayerWinPlatform.instance.getPlayerByTextureId(textureId)!;
    return WinVideoPlayer(controller);
  }

  /// Sets the audio mode to mix with other sources
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    // do nothing... not supported in Windows OS
  }
}
