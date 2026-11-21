import 'dart:async';
import 'dart:io';

import 'package:better_player_enhanced/better_player.dart';
// Better Player no exporta la superficie de vídeo ni el dibujador de
// subtítulos. Se importan para pintar solo el vídeo y conservar nuestra UI.
// ignore: implementation_imports
import 'package:better_player_enhanced/src/subtitles/better_player_subtitles_drawer.dart';
// ignore: implementation_imports
import 'package:better_player_enhanced/src/video_player/video_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'player_tuning.dart';

/// Capa común de reproducción.
///
/// En Android TV, Windows y Linux se usa libmpv a través de `media_kit`. En
/// Android móvil se usa Media3/ExoPlayer a través de `better_player_enhanced`,
/// que es el motor nativo que mejor se adapta a los formatos del portal sin
/// depender de librerías privadas de la APK original.
///
/// Los modelos de pistas (`Tracks`, `Track`, `AudioTrack`, `SubtitleTrack`)
/// siguen siendo los de `media_kit`: son clases de datos puras y permiten
/// conservar la interfaz y la lógica de selección del reproductor tal cual.
abstract class PlaybackEngine {
  Stream<bool> get playing;
  Stream<bool> get buffering;
  Stream<double> get volume;
  Stream<String> get error;
  Stream<bool> get completed;
  Stream<int?> get height;
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<Tracks> get tracks;
  Stream<Track> get track;

  /// Volumen inicial, en el rango 0..100 que usa la interfaz.
  double get initialVolume;

  Future<void> open(String url, {Map<String, String> headers = const {}});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// [value] está en el rango 0..100.
  Future<void> setVolume(double value);
  Future<void> setSubtitleTrack(SubtitleTrack track);
  Future<void> setAudioTrack(AudioTrack track);

  Widget buildVideo({BoxFit fit = BoxFit.contain, Color fill = Colors.black});

  Future<void> dispose();
}

/// Selecciona el motor según el dispositivo. Android TV se queda con libmpv:
/// su perfil de decodificación (OpenGL + software) es el que evita los tirones
/// en la TV y no debe sustituirse por Media3.
PlaybackEngine createPlaybackEngine({required bool isTv}) {
  final useMedia3 = !kIsWeb && Platform.isAndroid && !isTv;
  return useMedia3 ? Media3PlaybackEngine() : MpvPlaybackEngine(isTv: isTv);
}

/// Motor basado en libmpv (Android TV, Windows, Linux y web).
class MpvPlaybackEngine implements PlaybackEngine {
  MpvPlaybackEngine({required bool isTv}) {
    _player = Player(
      configuration: PlayerTuning.playerConfiguration(isTv: isTv),
    );
    _controller = VideoController(
      _player,
      configuration: PlayerTuning.videoConfiguration(isTv: isTv),
    );
    unawaited(PlayerTuning.applyNativeTuning(_player, isTv: isTv));
  }

  late final Player _player;
  late final VideoController _controller;

  @override
  Stream<bool> get playing => _player.stream.playing;

  @override
  Stream<bool> get buffering => _player.stream.buffering;

  @override
  Stream<double> get volume => _player.stream.volume;

  @override
  Stream<String> get error => _player.stream.error;

  @override
  Stream<bool> get completed => _player.stream.completed;

  @override
  Stream<int?> get height => _player.stream.height;

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<Duration> get duration => _player.stream.duration;

  @override
  Stream<Tracks> get tracks => _player.stream.tracks;

  @override
  Stream<Track> get track => _player.stream.track;

  @override
  double get initialVolume => _player.state.volume;

  @override
  Future<void> open(String url, {Map<String, String> headers = const {}}) {
    return _player.open(Media(url, httpHeaders: headers), play: true);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double value) => _player.setVolume(value);

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) =>
      _player.setSubtitleTrack(track);

  @override
  Future<void> setAudioTrack(AudioTrack track) => _player.setAudioTrack(track);

  @override
  Widget buildVideo({BoxFit fit = BoxFit.contain, Color fill = Colors.black}) {
    return Video(
      controller: _controller,
      controls: NoVideoControls,
      fit: fit,
      fill: fill,
    );
  }

  @override
  Future<void> dispose() => _player.dispose();
}

/// Motor nativo de Android móvil basado en AndroidX Media3/ExoPlayer.
class Media3PlaybackEngine implements PlaybackEngine {
  Media3PlaybackEngine() {
    _controller = BetterPlayerController(
      const BetterPlayerConfiguration(
        autoPlay: false,
        showPlaceholderUntilPlay: false,
        handleLifecycle: false,
      ),
    );
    _controller.addEventsListener(_onEvent);
  }

  late final BetterPlayerController _controller;
  VideoPlayerController? _listened;
  Map<String, String> _headers = const <String, String>{};
  bool _disposed = false;

  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<bool> _buffering = StreamController<bool>.broadcast();
  final StreamController<double> _volume = StreamController<double>.broadcast();
  final StreamController<String> _error = StreamController<String>.broadcast();
  final StreamController<bool> _completed = StreamController<bool>.broadcast();
  final StreamController<int?> _height = StreamController<int?>.broadcast();
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration =
      StreamController<Duration>.broadcast();
  final StreamController<Tracks> _tracks = StreamController<Tracks>.broadcast();
  final StreamController<Track> _track = StreamController<Track>.broadcast();

  final Map<String, Object?> _last = <String, Object?>{};
  Track _currentTrack = const Track();
  String _lastTracksSignature = _resetSignature;

  static const String _resetSignature = '\u0000reset';
  DateTime? _lastErrorAt;

  /// Cambia cuando Better Player ha vuelto a parsear los subtítulos. Lo usa
  /// [Media3VideoView] para reconstruir la capa de texto.
  final ValueNotifier<int> subtitleRevision = ValueNotifier<int>(0);

  /// Solo para [Media3VideoView].
  BetterPlayerController get controller => _controller;

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<bool> get buffering => _buffering.stream;

  @override
  Stream<double> get volume => _volume.stream;

  @override
  Stream<String> get error => _error.stream;

  @override
  Stream<bool> get completed => _completed.stream;

  @override
  Stream<int?> get height => _height.stream;

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<Duration> get duration => _duration.stream;

  @override
  Stream<Tracks> get tracks => _tracks.stream;

  @override
  Stream<Track> get track => _track.stream;

  @override
  double get initialVolume => 100;

  void _emit<T>(String key, StreamController<T> controller, T value) {
    if (_disposed || controller.isClosed) return;
    if (_last[key] == value) return;
    _last[key] = value;
    controller.add(value);
  }

  void _emitError(String message) {
    if (_disposed || _error.isClosed) return;
    final now = DateTime.now();
    if (_lastErrorAt != null &&
        now.difference(_lastErrorAt!) < const Duration(milliseconds: 800)) {
      return;
    }
    _lastErrorAt = now;
    _error.add(message);
  }

  void _onValueChanged() {
    if (_disposed) return;
    final video = _controller.videoPlayerController;
    if (video == null) return;
    final value = video.value;

    _emit('playing', _playing, value.isPlaying);
    _emit('buffering', _buffering, value.isBuffering);
    _emit('volume', _volume, (value.volume * 100).round().toDouble());
    _emit('position', _position, value.position);
    _emit('duration', _duration, value.duration ?? Duration.zero);
    final height = value.size?.height.round();
    if (height != null) _emit('height', _height, height);
    _maybeEmitTracks();
  }

  void _maybeEmitTracks() {
    if (_disposed) return;
    final audios =
        _controller.betterPlayerAsmsAudioTracks ??
        <BetterPlayerAsmsAudioTrack>[];
    final subtitles = _controller.betterPlayerSubtitlesSourceList;
    final signature = <String>[
      for (final audio in audios)
        'a:${audio.id}:${audio.label}:${audio.language}',
      for (final subtitle in subtitles)
        's:${subtitle.type}:${subtitle.urls?.join(',') ?? subtitle.name}',
    ].join('|');
    if (signature == _lastTracksSignature) return;
    _lastTracksSignature = signature;

    final audioTracks = <AudioTrack>[
      for (var i = 0; i < audios.length; i++)
        AudioTrack(
          (audios[i].id ?? i).toString(),
          audios[i].label,
          audios[i].language,
          isDefault: i == 0,
        ),
    ];
    final subtitleTracks = <SubtitleTrack>[
      for (final subtitle in subtitles)
        if (subtitle.type != null &&
            subtitle.type != BetterPlayerSubtitlesSourceType.none)
          SubtitleTrack(
            subtitle.urls?.firstWhere(
                  (url) => url != null,
                  orElse: () => subtitle.name,
                ) ??
                subtitle.name ??
                'subtitle',
            subtitle.name,
            null,
            isDefault: subtitle.selectedByDefault,
          ),
    ];

    _emit(
      'tracks',
      _tracks,
      Tracks(
        audio: audioTracks.isEmpty
            ? <AudioTrack>[AudioTrack.auto(), AudioTrack.no()]
            : audioTracks,
        subtitle: subtitleTracks,
      ),
    );
  }

  void _onEvent(BetterPlayerEvent event) {
    if (_disposed) return;
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.finished:
        if (!_completed.isClosed) _completed.add(true);
        break;
      case BetterPlayerEventType.exception:
        _emitError(
          event.parameters?['exception']?.toString() ??
              'Error de reproducción de Media3',
        );
        break;
      case BetterPlayerEventType.changedSubtitles:
        subtitleRevision.value++;
        _maybeEmitTracks();
        break;
      case BetterPlayerEventType.changedTrack:
        _maybeEmitTracks();
        break;
      case BetterPlayerEventType.setupDataSource:
        _lastTracksSignature = _resetSignature;
        _currentTrack = const Track();
        _emit('track', _track, _currentTrack);
        _maybeEmitTracks();
        break;
      default:
        break;
    }
  }

  void _attachValueListener() {
    final video = _controller.videoPlayerController;
    if (video == null || identical(video, _listened)) return;
    _listened?.removeListener(_onValueChanged);
    _listened = video;
    video.addListener(_onValueChanged);
    _onValueChanged();
  }

  @override
  Future<void> open(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    if (_disposed) return;
    _headers = headers;
    await _controller.setupDataSource(
      BetterPlayerDataSource.network(
        url,
        headers: headers.isEmpty ? null : headers,
      ),
    );
    if (_disposed) return;
    _attachValueListener();
    await _controller.play();
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    await _controller.play();
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    await _controller.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    final video = _controller.videoPlayerController;
    // En directos no hay duración: un seek no tiene sentido y Better Player
    // lanzaría un StateError.
    if (video == null || video.value.duration == null) return;
    await _controller.seekTo(position);
  }

  @override
  Future<void> setVolume(double value) async {
    if (_disposed) return;
    await _controller.setVolume((value / 100).clamp(0.0, 1.0));
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    if (_disposed) return;
    if (track.id == 'no') {
      await _controller.setupSubtitleSource(
        BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.none),
      );
      _currentTrack = _currentTrack.copyWith(subtitle: SubtitleTrack.no());
      _emit('track', _track, _currentTrack);
      return;
    }
    if (track.uri) {
      await _controller.setupSubtitleSource(
        BetterPlayerSubtitlesSource(
          type: BetterPlayerSubtitlesSourceType.network,
          name: track.title ?? 'Subtítulos',
          urls: <String>[track.id],
          headers: _headers.isEmpty ? null : _headers,
          selectedByDefault: true,
        ),
      );
      _currentTrack = _currentTrack.copyWith(subtitle: track);
      _emit('track', _track, _currentTrack);
      return;
    }
    final subtitle = _controller.betterPlayerSubtitlesSourceList.firstWhere(
      (source) =>
          (source.urls?.firstWhere(
                (url) => url != null,
                orElse: () => source.name,
              ) ??
              source.name) ==
          track.id,
      orElse: () => BetterPlayerSubtitlesSource(
        type: BetterPlayerSubtitlesSourceType.none,
      ),
    );
    await _controller.setupSubtitleSource(subtitle);
    _currentTrack = _currentTrack.copyWith(subtitle: track);
    _emit('track', _track, _currentTrack);
  }

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    if (_disposed || track.id == 'no' || track.id == 'auto') return;
    final id = int.tryParse(track.id);
    final audio =
        _controller.betterPlayerAsmsAudioTracks?.firstWhere(
          (item) => item.id == id || (id == null && item.label == track.title),
          orElse: () => BetterPlayerAsmsAudioTrack(
            id: id,
            label: track.title,
            language: track.language,
          ),
        ) ??
        BetterPlayerAsmsAudioTrack(
          id: id,
          label: track.title,
          language: track.language,
        );
    _controller.setAudioTrack(audio);
    _currentTrack = _currentTrack.copyWith(audio: track);
    _emit('track', _track, _currentTrack);
  }

  @override
  Widget buildVideo({BoxFit fit = BoxFit.contain, Color fill = Colors.black}) {
    return Media3VideoView(engine: this, fit: fit, fill: fill);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _controller.removeEventsListener(_onEvent);
    _listened?.removeListener(_onValueChanged);
    subtitleRevision.dispose();
    await Future.wait<void>(<Future<void>>[
      _playing.close(),
      _buffering.close(),
      _volume.close(),
      _error.close(),
      _completed.close(),
      _height.close(),
      _position.close(),
      _duration.close(),
      _tracks.close(),
      _track.close(),
    ]);
    _controller.dispose();
  }
}

/// Superficie de vídeo de Media3.
///
/// Se usa el `VideoPlayer` interno de Better Player en lugar del widget
/// `BetterPlayer` completo: así conservamos nuestros propios controles y
/// overlays mientras Media3 se encarga solo de decodificar y pintar.
class Media3VideoView extends StatefulWidget {
  const Media3VideoView({
    super.key,
    required this.engine,
    required this.fit,
    required this.fill,
  });

  final Media3PlaybackEngine engine;
  final BoxFit fit;
  final Color fill;

  @override
  State<Media3VideoView> createState() => _Media3VideoViewState();
}

class _Media3VideoViewState extends State<Media3VideoView> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.engine.subtitleRevision,
      builder: (context, _, _) {
        final controller = widget.engine.controller;
        final video = controller.videoPlayerController;
        final subtitles = controller.subtitlesLines;

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: widget.fill),
            if (video != null)
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: video,
                builder: (context, value, _) {
                  final size = value.size;
                  if (!value.initialized || size == null) {
                    return const SizedBox.expand();
                  }
                  return Center(
                    child: FittedBox(
                      fit: widget.fit,
                      child: SizedBox(
                        width: size.width,
                        height: size.height,
                        child: VideoPlayer(video),
                      ),
                    ),
                  );
                },
              ),
            if (video != null && subtitles.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: BetterPlayerSubtitlesDrawer(
                    subtitles: subtitles,
                    betterPlayerController: controller,
                    playerVisibilityStream: Stream<bool>.value(false),
                    betterPlayerSubtitlesConfiguration:
                        const BetterPlayerSubtitlesConfiguration(
                          fontSize: 15,
                          bottomPadding: 78,
                        ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
