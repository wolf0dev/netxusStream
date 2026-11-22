import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_layout.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../core/channel_categories.dart';
import '../core/formatters.dart';
import '../core/playback_engine.dart';
import '../core/player_tuning.dart';
import '../models/channel.dart';
import '../models/vod_resume.dart';
import '../services/resume_service.dart';
import '../state/app_state.dart';
import '../widgets/channel_logo.dart';
import '../widgets/neon_spinner.dart';
import '../widgets/nexus_focusable.dart';
import '../widgets/search_field.dart';

/// Abre el reproductor a pantalla completa y guarda el canal como último visto.
///
/// Si se pasa [resume], el reproductor salta a la posición guardada y va
/// actualizando el progreso mientras se reproduce.
Future<void> openChannelPlayer(
  BuildContext context,
  Channel channel, {
  VodResume? resume,
}) {
  final app = AppScope.read(context);
  app.rememberChannel(channel);
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      fullscreenDialog: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) =>
          PlayerScreen(initialChannel: channel, initialResume: resume),
      transitionsBuilder: (_, animation, _, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    ),
  );
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.initialChannel,
    this.initialResume,
  });

  final Channel initialChannel;

  /// Progreso guardado de este título (solo VOD).
  final VodResume? initialResume;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late PlaybackEngine _engine;
  late Channel _channel;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final FocusNode _rootFocus = FocusNode(debugLabel: 'PlayerRoot');
  final FocusNode _playFocus = FocusNode(debugLabel: 'PlayerPlay');

  Timer? _hideTimer;
  Timer? _retryTimer;
  Timer? _stabilityTimer;
  Timer? _bufferTimer;
  Timer? _stallTimer;
  bool _playing = false;
  bool _buffering = true;
  bool _loading = true;
  bool _reconnecting = false;
  bool _signalLost = false;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  bool _startedOnce = false;
  int _retryAttempt = 0;
  DateTime _ignoreCompletedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  double _volume = 100;
  double _lastAudibleVolume = 100;
  String? _error;
  String? _quality;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  /// Estado global capturado en `initState`: en `dispose` el `context` ya no
  /// es seguro para consultar inherited widgets.
  late final AppState _app;
  VodResume? _activeResume;
  bool _resumeApplied = false;
  bool _resumeFinished = false;
  DateTime _lastResumeSave = DateTime.fromMillisecondsSinceEpoch(0);

  Tracks _tracks = const Tracks();
  Track _selectedTrack = const Track();

  /// URL del subtítulo externo activo (los VOD no traen pistas incrustadas).
  String? _externalSubtitleUrl;
  bool _subtitleChoiceTouched = false;
  bool _applyingSubtitle = false;

  /// Tiempo máximo de búfer congelado antes de considerar la señal perdida.
  static const Duration _stallTimeout = Duration(seconds: 18);

  /// Si la reproducción falló, el siguiente intento fuerza credenciales nuevas
  /// del portal (por si el CDN invalidó el token antes de la hora prevista).
  bool _forceCredentialRefresh = false;

  @override
  void initState() {
    super.initState();
    _app = AppScope.read(context);
    _activeResume = widget.initialResume;
    _channel = widget.initialChannel;
    final isTv = _app.layout.isTv;
    _engine = createPlaybackEngine(isTv: isTv);
    _fullscreen = !kIsWeb && Platform.isAndroid;
    _volume = _engine.initialVolume;
    _lastAudibleVolume = _volume > 0 ? _volume : 100;

    // Forzar landscape en Android móvil
    if (!kIsWeb && Platform.isAndroid) {
      unawaited(
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
    }

    _subscriptions.add(
      _engine.playing.listen((value) {
        if (!mounted) return;
        if (value) {
          _startedOnce = true;
          _bufferTimer?.cancel();
          _stallTimer?.cancel();
          _stabilityTimer?.cancel();
          if (!_subtitleChoiceTouched &&
              _externalSubtitleUrl == null &&
              _channel.subtitles.isNotEmpty) {
            unawaited(_applyPreferredSubtitle());
          }
          _stabilityTimer = Timer(const Duration(seconds: 6), () {
            if (!mounted) return;
            // Solo reiniciamos el contador cuando la señal se mantiene
            // estable; así evitamos bucles infinitos de reconexión.
            _retryAttempt = 0;
          });
        } else {
          _stabilityTimer?.cancel();
        }
        setState(() {
          _playing = value;
          if (value) {
            _loading = false;
            _buffering = false;
            _reconnecting = false;
            _signalLost = false;
            _error = null;
            _retryTimer?.cancel();
          }
        });
        if (value) {
          _showControls();
        } else {
          _showControls(autoHide: false);
        }
      }),
    );
    _subscriptions.add(
      _engine.buffering.listen((value) {
        if (!mounted) return;
        _bufferTimer?.cancel();
        if (!value) {
          _stallTimer?.cancel();
          if (_buffering) setState(() => _buffering = false);
          return;
        }
        // Pequeño antirrebote para que un microcorte no haga parpadear el
        // spinner sobre la imagen.
        if (_buffering) return;
        _bufferTimer = Timer(const Duration(milliseconds: 450), () {
          if (!mounted) return;
          setState(() => _buffering = true);
          _armStallWatchdog();
        });
      }),
    );
    _subscriptions.add(
      _engine.volume.listen((value) {
        if (!mounted) return;
        setState(() {
          _volume = value;
          if (value > 0) _lastAudibleVolume = value;
        });
      }),
    );
    _subscriptions.add(
      _engine.error.listen((error) {
        if (!mounted) return;
        debugPrint('Error del motor de reproducción: $error');
        _registerFailure(_friendlyError(error));
      }),
    );
    _subscriptions.add(
      _engine.completed.listen((value) {
        if (!mounted || !value) return;
        // Ignoramos los cierres provocados al abrir un canal nuevo.
        if (DateTime.now().isBefore(_ignoreCompletedUntil)) return;
        if (!_startedOnce) return;
        final resume = _activeResume;
        if (_channel.isVod && resume != null) {
          // Un VOD que termina no es una señal perdida: borramos el progreso
          // para que no vuelva a aparecer en «Continuar viendo».
          _resumeFinished = true;
          _app.clearVodResume(resume.key);
          return;
        }
        _registerFailure(
          'La señal se interrumpió. Intentando reconectar automáticamente…',
        );
      }),
    );
    _subscriptions.add(
      _engine.height.listen((height) {
        if (!mounted || height == null) return;
        setState(() => _quality = _qualityFor(height));
      }),
    );
    _subscriptions.add(
      _engine.position.listen((position) {
        if (!mounted) return;
        setState(() => _position = position);
        _maybeApplyResume();
        _saveResumeProgress(position);
      }),
    );
    _subscriptions.add(
      _engine.duration.listen((duration) {
        if (!mounted) return;
        setState(() => _duration = duration);
        _maybeApplyResume();
      }),
    );
    _subscriptions.add(
      _engine.tracks.listen((tracks) {
        if (!mounted) return;
        setState(() => _tracks = tracks);
      }),
    );
    _subscriptions.add(
      _engine.track.listen((track) {
        if (!mounted) return;
        setState(() => _selectedTrack = track);
      }),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_fullscreen) unawaited(_applyAndroidFullscreen(true));
      unawaited(_start(_channel));
      _showControls(autoHide: false);
    });
  }

  @override
  void dispose() {
    // Guardamos también al cerrar (back, pantalla de inicio, cambio de app):
    // el evento `position` puede no haber llegado en los últimos 5 segundos.
    _saveResumeProgress(_position, force: true, notify: false);
    _hideTimer?.cancel();
    _retryTimer?.cancel();
    _stabilityTimer?.cancel();
    _bufferTimer?.cancel();
    _stallTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_engine.dispose());
    if (!kIsWeb && Platform.isAndroid) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      unawaited(
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
    }
    if (isDesktopPlatform && _fullscreen) {
      unawaited(windowManager.setFullScreen(false));
    }
    _rootFocus.dispose();
    _playFocus.dispose();
    super.dispose();
  }

  /// Salta una sola vez a la posición guardada en cuanto el reproductor
  /// empieza a emitir posiciones (los `.ts` del portal no siempre informan de
  /// su duración, así que no podemos esperar solo al stream `duration`).
  void _maybeApplyResume() {
    final resume = _activeResume;
    if (resume == null || _resumeApplied || !_startedOnce) return;
    final target = ResumeService.seekTarget(resume.position, _duration);
    if (target <= Duration.zero) {
      _resumeApplied = true;
      return;
    }
    if (_duration <= Duration.zero && _position < const Duration(seconds: 1)) {
      return;
    }
    _resumeApplied = true;
    debugPrint('VOD: reanudando en ${target.inSeconds}s');
    unawaited(_engine.seek(target));
  }

  /// Registra el punto exacto de reproducción, con un límite de escrituras.
  void _saveResumeProgress(
    Duration position, {
    bool force = false,
    bool notify = true,
  }) {
    final resume = _activeResume;
    if (resume == null || _resumeFinished) return;

    if (ResumeService.isFinished(position, _duration)) {
      _resumeFinished = true;
      _app.clearVodResume(resume.key, notify: notify);
      return;
    }
    if (!force && !ResumeService.shouldSave(position, _duration)) return;
    // Al cerrar guardamos aunque no hayan pasado 5 s, pero no creamos una
    // entrada vacía si el vídeo nunca llegó a reproducirse.
    if (force && position <= Duration.zero) return;

    final now = DateTime.now();
    if (!force &&
        now.difference(_lastResumeSave) < ResumeService.saveInterval) {
      return;
    }
    _lastResumeSave = now;
    _activeResume = resume.copyWith(
      positionMs: position.inMilliseconds,
      durationMs: _duration.inMilliseconds,
      updatedAt: now,
    );
    _app.rememberVodResume(_activeResume!, notify: notify);
  }

  Future<void> _start(Channel channel) async {
    if (!mounted) return;
    _retryTimer?.cancel();
    _stabilityTimer?.cancel();
    _stallTimer?.cancel();
    // Un retry vuelve a abrir el archivo desde cero: hay que reanudarlo de
    // nuevo y volver a guardar la posición real.
    _resumeApplied = false;
    _resumeFinished = false;
    _lastResumeSave = DateTime.fromMillisecondsSinceEpoch(0);
    setState(() {
      _channel = channel;
      _error = null;
      _signalLost = false;
      _reconnecting = false;
      _retryAttempt = 0;
      _startedOnce = false;
      _loading = true;
      _buffering = true;
      _quality = null;
      _playing = false;
      _tracks = const Tracks();
      _selectedTrack = const Track();
      _externalSubtitleUrl = null;
      _subtitleChoiceTouched = false;
      _applyingSubtitle = false;
    });
    _forceCredentialRefresh = false;
    AppScope.read(context).rememberChannel(channel);
    _armStartupWatchdog();
    await _openStream();
  }

  Future<void> _openStream() async {
    if (!mounted) return;
    // Los cierres del stream anterior llegan de forma asíncrona: ignoramos los
    // eventos `completed` durante la ventana de apertura.
    _ignoreCompletedUntil = DateTime.now().add(const Duration(seconds: 2));

    // Portal Wiwy: renueva `userToken`/`Content-Auth` si están por caducar.
    // El refresco solo toca la red cuando hace falta; si falla, se intenta
    // reproducir con las credenciales que ya tengamos. Tras un fallo se fuerza
    // la renovación (con límite de frecuencia) por si el CDN invalidó el token.
    final app = AppScope.read(context);
    // Los títulos VOD no usan los tokens de directo: no hace falta (ni conviene)
    // refrescar la lista completa antes de abrir la película.
    if (app.useWiwy && !_channel.isVod) {
      final force = _forceCredentialRefresh;
      _forceCredentialRefresh = false;
      try {
        await app
            .ensureFreshStream(force: force)
            .timeout(const Duration(seconds: 15));
      } catch (error) {
        debugPrint('No se pudieron renovar las credenciales: $error');
      }
      if (!mounted) return;
    }

    // Debug: mostrar URL y headers
    debugPrint('=== Reproduciendo ===');
    debugPrint('URL: ${_channel.url}');
    debugPrint('Headers: ${_channel.httpHeaders}');

    try {
      await _engine.open(_channel.url, headers: _channel.httpHeaders);
      unawaited(_applyPreferredSubtitle());
    } catch (error) {
      if (!mounted) return;
      _registerFailure(_friendlyError(error.toString()));
    }
  }

  /// Gestiona un corte de señal: reintenta en silencio hasta
  /// [PlayerTuning.maxRetries] veces y, solo entonces, avisa al usuario con
  /// un aviso discreto (nunca un diálogo de error sobre el video).
  void _registerFailure(String message) {
    if (!mounted) return;
    _stallTimer?.cancel();
    if (_retryAttempt < PlayerTuning.maxRetries && !_signalLost) {
      // El fallo puede ser un token revocado: el reintento pide credenciales.
      _forceCredentialRefresh = !_channel.isVod;
      _scheduleSilentRetry();
      return;
    }
    _stabilityTimer?.cancel();
    setState(() {
      _loading = false;
      _buffering = false;
      _playing = false;
      _reconnecting = false;
      _signalLost = true;
      _error = message;
      _controlsVisible = true;
    });
  }

  void _scheduleSilentRetry() {
    if (_retryTimer?.isActive ?? false) return;
    _stallTimer?.cancel();
    _retryAttempt += 1;
    setState(() {
      _loading = false;
      _buffering = true;
      _playing = false;
      _reconnecting = true;
      _signalLost = false;
      _error = null;
      _controlsVisible = true;
    });
    _hideTimer?.cancel();
    _retryTimer = Timer(PlayerTuning.retryDelay, () {
      if (!mounted) return;
      unawaited(_silentRetry());
    });
  }

  Future<void> _silentRetry() async {
    if (!mounted) return;
    setState(() {
      _reconnecting = true;
      _buffering = true;
    });
    // En Android TV el primer reintento conserva MediaCodec pero baja de
    // Vulkan a OpenGL; los siguientes degradan el decoder solo si hace falta.
    if (_retryAttempt > 0) {
      await _engine.applyRecovery(_retryAttempt);
    }
    _armStartupWatchdog();
    await _openStream();
  }

  /// Si el canal no empieza a reproducir en un tiempo razonable, se asume
  /// que la conexión quedó colgada y se pasa al siguiente intento.
  void _armStartupWatchdog() {
    _stallTimer?.cancel();
    _stallTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted || _signalLost || _playing) return;
      _registerFailure(
        '${_channel.name} tardó demasiado en responder. Reintentando…',
      );
    });
  }

  /// Si el búfer se queda congelado sin errores de red explícitos, forzamos
  /// la reconexión pasados [_stallTimeout].
  void _armStallWatchdog() {
    _stallTimer?.cancel();
    _stallTimer = Timer(_stallTimeout, () {
      if (!mounted || _signalLost || _reconnecting || _loading) return;
      if (!_buffering) return;
      _registerFailure(
        'La señal dejó de recibir datos. Reintentando automáticamente…',
      );
    });
  }

  Future<void> _retry() async {
    _retryTimer?.cancel();
    _retryAttempt = 0;
    _signalLost = false;
    _error = null;
    await _start(_channel);
  }

  Future<void> _togglePlay() async {
    if (_signalLost) {
      await _retry();
      return;
    }
    if (_playing) {
      await _engine.pause();
    } else {
      await _engine.play();
    }
    _showControls();
  }

  void _toggleMute() {
    if (_volume > 0) {
      _lastAudibleVolume = _volume;
      unawaited(_engine.setVolume(0));
    } else {
      unawaited(
        _engine.setVolume(_lastAudibleVolume <= 0 ? 100 : _lastAudibleVolume),
      );
    }
    _showControls();
  }

  void _setVolume(double value) {
    setState(() {
      _volume = value;
      if (value > 0) _lastAudibleVolume = value;
    });
    unawaited(_engine.setVolume(value));
    _showControls();
  }

  /// Salta [seconds] hacia atrás o adelante dentro de un título VOD.
  void _seekRelative(int seconds) {
    if (_duration <= Duration.zero) return;
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    unawaited(_engine.seek(clamped));
    _showControls();
  }

  /// Menú inferior del reproductor Android, con el estilo de VLC.
  Future<void> _openAndroidMenu() async {
    _showControls(autoHide: false);
    final app = AppScope.read(context);
    final isFavorite = app.isFavorite(_channel);
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFF16171B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 10),
            _SheetAction(
              icon: Icons.playlist_play_rounded,
              label: 'Cambiar de canal',
              onTap: () => Navigator.of(sheetContext).pop('channels'),
            ),
            if (_hasAudioChoice)
              _SheetAction(
                icon: Icons.audiotrack_rounded,
                label: 'Idioma de audio',
                onTap: () => Navigator.of(sheetContext).pop('audio'),
              ),
            if (_hasSubtitleChoice)
              _SheetAction(
                icon: Icons.subtitles_rounded,
                label: 'Subtítulos',
                onTap: () => Navigator.of(sheetContext).pop('subtitles'),
              ),
            _SheetAction(
              icon: isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: isFavorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
              accent: isFavorite ? const Color(0xFFFB7185) : null,
              onTap: () => Navigator.of(sheetContext).pop('favorite'),
            ),
            _SheetAction(
              icon: _fullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              label: _fullscreen
                  ? 'Salir de pantalla completa'
                  : 'Pantalla completa',
              onTap: () => Navigator.of(sheetContext).pop('fullscreen'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'channels':
        await _openChannelPicker();
        break;
      case 'audio':
        await _pickAudioTrack();
        break;
      case 'subtitles':
        await _pickSubtitleTrack();
        break;
      case 'favorite':
        _toggleFavorite();
        break;
      case 'fullscreen':
        await _toggleFullscreen();
        break;
    }
    if (mounted) _showControls(autoHide: false);
  }

  // Pistas de audio y subtítulos --------------------------------------------

  /// Pistas de audio reales (la lista de media_kit incluye `auto` y `no`).
  List<AudioTrack> get _audioTracks =>
      _tracks.audio.where((track) => track.id != 'no').toList(growable: false);

  /// Subtítulos externos que entrega el portal para este título. Se generan
  /// como pistas de `media_kit` a partir de la URL del `.srt`.
  List<SubtitleTrack> get _externalSubtitleTracks => [
    for (final subtitle in _channel.subtitles)
      SubtitleTrack.uri(
        subtitle.url,
        title: _externalSubtitleLabel(subtitle),
        language: subtitle.language.isEmpty ? null : subtitle.language,
      ),
  ];

  /// Subtítulos disponibles: incrustados en el archivo + externos del portal.
  List<SubtitleTrack> get _subtitleTracks {
    final embedded = _tracks.subtitle.where(
      (track) => track.id != 'auto' && track.id != 'no' && !track.uri,
    );
    return <SubtitleTrack>[...embedded, ..._externalSubtitleTracks];
  }

  bool get _hasAudioChoice => _audioTracks.length > 1;
  bool get _hasSubtitleChoice => _subtitleTracks.isNotEmpty;

  String _externalSubtitleLabel(ChannelSubtitle subtitle) {
    final label = subtitle.label.trim();
    if (label.isNotEmpty) return label;
    final language = ChannelCategories.languageName(subtitle.language);
    return language.isNotEmpty ? language : 'Subtítulos';
  }

  /// Activa el subtítulo en español (o el primero) en cuanto el vídeo empieza.
  Future<void> _applyPreferredSubtitle() async {
    if (_applyingSubtitle ||
        _subtitleChoiceTouched ||
        _externalSubtitleUrl != null ||
        _channel.subtitles.isEmpty) {
      return;
    }
    final preferred = _preferredSubtitle(_channel.subtitles);
    if (preferred == null) return;

    _applyingSubtitle = true;
    try {
      await _engine.setSubtitleTrack(
        SubtitleTrack.uri(
          preferred.url,
          title: _externalSubtitleLabel(preferred),
          language: preferred.language.isEmpty ? null : preferred.language,
        ),
      );
      if (!mounted) return;
      setState(() => _externalSubtitleUrl = preferred.url);
      debugPrint('Subtítulos activados: ${_externalSubtitleLabel(preferred)}');
    } catch (error) {
      debugPrint('No se pudieron activar los subtítulos: $error');
    } finally {
      _applyingSubtitle = false;
    }
  }

  /// Prefiere español; si no hay, usa el primer subtítulo disponible.
  ChannelSubtitle? _preferredSubtitle(List<ChannelSubtitle> subtitles) {
    for (final subtitle in subtitles) {
      final language = subtitle.language.toLowerCase();
      if (language == 'es' || language.startsWith('es-') || language == 'spa') {
        return subtitle;
      }
    }
    return subtitles.isEmpty ? null : subtitles.first;
  }

  Future<void> _pickAudioTrack() async {
    _showControls(autoHide: false);
    final selected = await showDialog<AudioTrack>(
      context: context,
      builder: (context) => _TrackPickerDialog<AudioTrack>(
        title: 'Idioma de audio',
        icon: Icons.audiotrack_rounded,
        tracks: _audioTracks,
        selectedId: _selectedTrack.audio.id,
        idOf: (track) => track.id,
        labelOf: _audioLabel,
        detailOf: _audioDetail,
      ),
    );
    if (selected == null || !mounted) return;
    try {
      await _engine.setAudioTrack(selected);
    } catch (error) {
      debugPrint('No se pudo cambiar la pista de audio: $error');
    }
    _showControls(autoHide: false);
  }

  Future<void> _pickSubtitleTrack() async {
    _showControls(autoHide: false);
    final options = <SubtitleTrack>[SubtitleTrack.no(), ..._subtitleTracks];
    final selected = await showDialog<SubtitleTrack>(
      context: context,
      builder: (context) => _TrackPickerDialog<SubtitleTrack>(
        title: 'Subtítulos',
        icon: Icons.subtitles_rounded,
        tracks: options,
        selectedId: _externalSubtitleUrl ?? _selectedTrack.subtitle.id,
        idOf: (track) => track.id,
        labelOf: _subtitleLabel,
        detailOf: _subtitleDetail,
      ),
    );
    if (selected == null || !mounted) return;
    try {
      await _engine.setSubtitleTrack(selected);
      if (!mounted) return;
      setState(() {
        _subtitleChoiceTouched = true;
        _externalSubtitleUrl = selected.uri ? selected.id : null;
      });
    } catch (error) {
      debugPrint('No se pudo cambiar la pista de subtítulos: $error');
    }
    _showControls(autoHide: false);
  }

  String _audioLabel(AudioTrack track) {
    if (track.id == 'auto') return 'Automático';
    final title = track.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    final language = ChannelCategories.languageName(track.language);
    return language.isNotEmpty ? language : 'Pista ${track.id}';
  }

  String _audioDetail(AudioTrack track) {
    final parts = <String>[];
    final language = ChannelCategories.languageName(track.language);
    if (track.id != 'auto' && language.isNotEmpty) parts.add(language);
    final channels = track.channels?.trim() ?? '';
    if (channels.isNotEmpty) parts.add(channels);
    final codec = track.codec?.trim() ?? '';
    if (codec.isNotEmpty) parts.add(codec.toUpperCase());
    if (track.isDefault == true) parts.add('Predeterminada');
    return parts.join(' · ');
  }

  String _subtitleLabel(SubtitleTrack track) {
    if (track.id == 'no') return 'Desactivados';
    final title = track.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    final language = ChannelCategories.languageName(track.language);
    return language.isNotEmpty ? language : 'Subtítulo ${track.id}';
  }

  String _subtitleDetail(SubtitleTrack track) {
    if (track.id == 'no') return 'Sin texto en pantalla';
    final parts = <String>[];
    final language = ChannelCategories.languageName(track.language);
    if (language.isNotEmpty) parts.add(language);
    final codec = track.codec?.trim() ?? '';
    if (codec.isNotEmpty) parts.add(codec.toUpperCase());
    if (track.uri) {
      parts.add('Externo');
      final matches = _channel.subtitles.where((item) => item.url == track.id);
      if (matches.isNotEmpty) {
        final format = matches.first.format.trim();
        if (format.isNotEmpty) parts.add(format.toUpperCase());
      }
    }
    if (track.isDefault == true) parts.add('Predeterminados');
    return parts.join(' · ');
  }

  void _showControls({bool autoHide = true}) {
    _hideTimer?.cancel();
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    if (autoHide) _scheduleAutoHide();
  }

  void _scheduleAutoHide() {
    final app = AppScope.read(context);
    if (app.layout.isTv || !_playing || _signalLost) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_playing || _signalLost) return;
      if (_channelPickerOpen) return;
      _hideControls();
    });
  }

  bool _channelPickerOpen = false;

  void _hideControls() {
    _hideTimer?.cancel();
    if (!_controlsVisible) return;
    setState(() => _controlsVisible = false);
    _rootFocus.requestFocus();
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    if (isDesktopPlatform) {
      try {
        await windowManager.setFullScreen(next);
      } catch (error) {
        debugPrint('No se pudo cambiar pantalla completa: $error');
      }
    } else if (!kIsWeb && Platform.isAndroid) {
      await _applyAndroidFullscreen(next);
    }
    _showControls();
  }

  Future<void> _applyAndroidFullscreen(bool value) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await SystemChrome.setEnabledSystemUIMode(
      value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  Future<void> _openChannelPicker() async {
    _showControls(autoHide: false);
    _channelPickerOpen = true;
    final app = AppScope.read(context);
    final selected = await showDialog<Channel>(
      context: context,
      useSafeArea: true,
      builder: (_) =>
          ChannelPickerDialog(channels: app.channels, current: _channel),
    );
    _channelPickerOpen = false;
    if (!mounted) return;
    _rootFocus.requestFocus();
    if (selected != null && selected.url != _channel.url) {
      await _start(selected);
    }
    _showControls();
  }

  void _toggleFavorite() {
    final app = AppScope.read(context);
    final added = app.toggleFavorite(_channel);
    showAppSnackBar(
      context,
      added
          ? '${_channel.name} añadido a favoritos'
          : '${_channel.name} eliminado de favoritos',
      icon: added ? Icons.favorite_rounded : Icons.favorite_border_rounded,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (_fullscreen && isDesktopPlatform) {
        unawaited(_toggleFullscreen());
      } else if (_channelPickerOpen) {
        return KeyEventResult.ignored;
      } else {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyF) {
      unawaited(_toggleFullscreen());
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
      return KeyEventResult.handled;
    }

    final isActivate =
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter;
    if (isActivate && _rootFocus.hasPrimaryFocus) {
      if (!_controlsVisible) {
        _showControls();
        if (AppScope.read(context).layout.isTv) {
          _playFocus.requestFocus();
        }
      } else {
        unawaited(_togglePlay());
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyC && _controlsVisible) {
      unawaited(_openChannelPicker());
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String _friendlyError(String raw) {
    final normalized = raw.toLowerCase();
    if (normalized.contains('timeout') ||
        normalized.contains('timed out') ||
        normalized.contains('temporarily unavailable')) {
      return 'La señal tardó demasiado en responder. Revisa tu conexión o '
          'prueba con otro canal.';
    }
    if (normalized.contains('404') || normalized.contains('not found')) {
      return 'El canal ya no está disponible en la lista. Prueba con otro '
          'canal o actualiza la lista.';
    }
    if (normalized.contains('403') || normalized.contains('forbidden')) {
      return 'El proveedor del canal rechazó la conexión. Puede que la señal '
          'esté restringida a su país de origen.';
    }
    return 'No pudimos conectar con ${_channel.name}. El canal puede estar '
        'fuera de línea o usar un formato no compatible.';
  }

  static String _qualityFor(int height) {
    if (height >= 2000) return '4K';
    if (height >= 1000) return '1080p';
    if (height >= 700) return '720p';
    if (height >= 460) return '480p';
    return '${height}p';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final isTv = app.layout.isTv;
    final isFavorite = app.isFavorite(_channel);
    final android = !kIsWeb && Platform.isAndroid && !isTv;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: MouseRegion(
          cursor: isDesktopPlatform
              ? (_controlsVisible
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.none)
              : MouseCursor.defer,
          onHover: (_) => _showControls(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _engine.buildVideo(fit: BoxFit.contain, fill: Colors.black),
                // `media_kit` emite `buffering` también mientras la señal ya
                // se está reproduciendo. Mostrar el overlay en ese caso deja
                // el canal «Estabilizando…» para siempre en las TV con red
                // lenta. Solo lo mostramos si de verdad no hay imagen.
                if ((_loading || _reconnecting || (_buffering && !_playing)) &&
                    !_signalLost)
                  _BufferingOverlay(
                    channel: _channel,
                    reconnecting: _reconnecting,
                    attempt: _retryAttempt,
                    loading: _loading,
                  ),
                if (_signalLost)
                  _SignalLostBanner(
                    message: _error ?? 'La señal se interrumpió.',
                    channel: _channel,
                    onRetry: () => unawaited(_retry()),
                    onOpenChannels: () => unawaited(_openChannelPicker()),
                  ),
                _controlsLayer(
                  visible: _controlsVisible,
                  child: android
                      ? _AndroidTopBar(
                          channel: _channel,
                          isFavorite: isFavorite,
                          quality: _quality,
                          hasError: _signalLost,
                          onBack: () => Navigator.of(context).maybePop(),
                          onToggleFavorite: _toggleFavorite,
                          onMenu: () => unawaited(_openAndroidMenu()),
                        )
                      : _TopBar(
                          channel: _channel,
                          isFavorite: isFavorite,
                          quality: _quality,
                          hasError: _signalLost,
                          onBack: () => Navigator.of(context).maybePop(),
                          onToggleFavorite: _toggleFavorite,
                          onFullscreen: () => unawaited(_toggleFullscreen()),
                          fullscreen: _fullscreen,
                        ),
                ),
                if (!_playing &&
                    !_loading &&
                    !_buffering &&
                    !_reconnecting &&
                    !_signalLost)
                  Center(
                    child: _GlassButton(
                      icon: Icons.play_arrow_rounded,
                      tooltip: 'Reproducir',
                      onTap: () => unawaited(_togglePlay()),
                      size: 64,
                      iconSize: 34,
                    ),
                  ),
                _controlsLayer(
                  visible: _controlsVisible,
                  bottom: true,
                  child: android
                      ? _AndroidBottomBar(
                          channel: _channel,
                          playing: _playing,
                          volume: _volume,
                          quality: _quality,
                          fullscreen: _fullscreen,
                          position: _position,
                          duration: _duration,
                          showAudioPicker: _hasAudioChoice,
                          showSubtitlePicker: _hasSubtitleChoice,
                          audioActive:
                              _selectedTrack.audio.id != 'auto' &&
                              _selectedTrack.audio.id != 'no',
                          subtitleActive:
                              _externalSubtitleUrl != null ||
                              (_selectedTrack.subtitle.id != 'auto' &&
                                  _selectedTrack.subtitle.id != 'no'),
                          onAudio: () => unawaited(_pickAudioTrack()),
                          onSubtitle: () => unawaited(_pickSubtitleTrack()),
                          onPlayPause: () => unawaited(_togglePlay()),
                          onSkip: _seekRelative,
                          onToggleMute: _toggleMute,
                          onOpenChannels: () => unawaited(_openChannelPicker()),
                          onFullscreen: () => unawaited(_toggleFullscreen()),
                          onSeek: (duration) =>
                              unawaited(_engine.seek(duration)),
                          onMenu: () => unawaited(_openAndroidMenu()),
                        )
                      : _BottomBar(
                          channel: _channel,
                          playing: _playing,
                          volume: _volume,
                          quality: _quality,
                          isTv: isTv,
                          playFocus: _playFocus,
                          fullscreen: _fullscreen,
                          position: _position,
                          duration: _duration,
                          showAudioPicker: _hasAudioChoice,
                          showSubtitlePicker: _hasSubtitleChoice,
                          audioActive:
                              _selectedTrack.audio.id != 'auto' &&
                              _selectedTrack.audio.id != 'no',
                          subtitleActive:
                              _externalSubtitleUrl != null ||
                              (_selectedTrack.subtitle.id != 'auto' &&
                                  _selectedTrack.subtitle.id != 'no'),
                          onAudio: () => unawaited(_pickAudioTrack()),
                          onSubtitle: () => unawaited(_pickSubtitleTrack()),
                          onPlayPause: () => unawaited(_togglePlay()),
                          onToggleMute: _toggleMute,
                          onVolumeChanged: _setVolume,
                          onOpenChannels: () => unawaited(_openChannelPicker()),
                          onFullscreen: () => unawaited(_toggleFullscreen()),
                          onSeek: (duration) =>
                              unawaited(_engine.seek(duration)),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlsLayer({
    required bool visible,
    required Widget child,
    bool bottom = false,
  }) {
    return Positioned(
      left: 0,
      right: 0,
      top: bottom ? null : 0,
      bottom: bottom ? 0 : null,
      child: ExcludeFocus(
        excluding: !visible,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: child,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Superposiciones del reproductor
// ---------------------------------------------------------------------------

/// Naranja de VLC: solo se usa en los controles del reproductor Android.
const Color _vlcOrange = Color(0xFFFF8800);

String _formatPlaybackTime(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

/// Barra superior del reproductor en Android: título, favorito y menú.
class _AndroidTopBar extends StatelessWidget {
  const _AndroidTopBar({
    required this.channel,
    required this.isFavorite,
    required this.quality,
    required this.hasError,
    required this.onBack,
    required this.onToggleFavorite,
    required this.onMenu,
  });

  final Channel channel;
  final bool isFavorite;
  final String? quality;
  final bool hasError;
  final VoidCallback onBack;
  final VoidCallback onToggleFavorite;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final statusColor = hasError ? AppColors.danger : AppColors.success;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF0000000), Color(0x8A000000), Colors.transparent],
          stops: [0, 0.58, 1],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            _AndroidIconButton(
              icon: Icons.arrow_back_rounded,
              label: 'Volver',
              onTap: onBack,
              filled: true,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        channel.isVod ? 'A LA CARTA' : 'EN VIVO',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          channel.group,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                      if (quality != null) ...[
                        const SizedBox(width: 7),
                        _QualityChip(label: quality!),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            _AndroidIconButton(
              icon: isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: isFavorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
              onTap: onToggleFavorite,
              active: isFavorite,
              accent: const Color(0xFFFB7185),
            ),
            _AndroidIconButton(
              icon: Icons.more_vert_rounded,
              label: 'Más opciones',
              onTap: onMenu,
            ),
          ],
        ),
      ),
    );
  }
}

/// Panel inferior del reproductor Android, con la disposición de VLC.
class _AndroidBottomBar extends StatelessWidget {
  const _AndroidBottomBar({
    required this.channel,
    required this.playing,
    required this.volume,
    required this.quality,
    required this.fullscreen,
    required this.position,
    required this.duration,
    required this.showAudioPicker,
    required this.showSubtitlePicker,
    required this.audioActive,
    required this.subtitleActive,
    required this.onAudio,
    required this.onSubtitle,
    required this.onPlayPause,
    required this.onSkip,
    required this.onToggleMute,
    required this.onOpenChannels,
    required this.onFullscreen,
    required this.onSeek,
    required this.onMenu,
  });

  final Channel channel;
  final bool playing;
  final double volume;
  final String? quality;
  final bool fullscreen;
  final Duration position;
  final Duration duration;
  final bool showAudioPicker;
  final bool showSubtitlePicker;
  final bool audioActive;
  final bool subtitleActive;
  final VoidCallback onAudio;
  final VoidCallback onSubtitle;
  final VoidCallback onPlayPause;
  final ValueChanged<int> onSkip;
  final VoidCallback onToggleMute;
  final VoidCallback onOpenChannels;
  final VoidCallback onFullscreen;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final isVod = channel.isVod && duration.inMilliseconds > 0;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF20B0C0E), Color(0xFF08090B)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 18,
                8,
                compact ? 10 : 18,
                4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (isVod)
                    _AndroidSeekBar(
                      position: position,
                      duration: duration,
                      onSeek: onSeek,
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const _AndroidLivePill(),
                          if (quality != null) ...[
                            const SizedBox(width: 8),
                            _QualityChip(label: quality!),
                          ],
                          const Spacer(),
                          Text(
                            channel.isVod ? 'VOD' : 'DIRECTO',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      if (isVod)
                        _AndroidIconButton(
                          icon: Icons.replay_10_rounded,
                          label: 'Retroceder 10 segundos',
                          onTap: () => onSkip(-10),
                        ),
                      _AndroidIconButton(
                        icon: playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        label: playing ? 'Pausar' : 'Reproducir',
                        onTap: onPlayPause,
                        size: 52,
                        iconSize: 31,
                        primary: true,
                      ),
                      if (isVod)
                        _AndroidIconButton(
                          icon: Icons.forward_10_rounded,
                          label: 'Avanzar 10 segundos',
                          onTap: () => onSkip(10),
                        ),
                      const Spacer(),
                      if (!compact)
                        _AndroidIconButton(
                          icon: volume == 0
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          label: volume == 0 ? 'Activar sonido' : 'Silenciar',
                          onTap: onToggleMute,
                          active: volume == 0,
                        ),
                      if (showAudioPicker)
                        _AndroidIconButton(
                          icon: Icons.audiotrack_rounded,
                          label: 'Idioma de audio',
                          onTap: onAudio,
                          active: audioActive,
                        ),
                      if (showSubtitlePicker)
                        _AndroidIconButton(
                          icon: Icons.subtitles_rounded,
                          label: 'Subtítulos',
                          onTap: onSubtitle,
                          active: subtitleActive,
                        ),
                      _AndroidIconButton(
                        icon: Icons.playlist_play_rounded,
                        label: 'Cambiar de canal',
                        onTap: onOpenChannels,
                      ),
                      if (!compact)
                        _AndroidIconButton(
                          icon: fullscreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          label: fullscreen
                              ? 'Salir de pantalla completa'
                              : 'Pantalla completa',
                          onTap: onFullscreen,
                        ),
                      if (compact)
                        _AndroidIconButton(
                          icon: Icons.more_vert_rounded,
                          label: 'Más opciones',
                          onTap: onMenu,
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AndroidSeekBar extends StatelessWidget {
  const _AndroidSeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final value = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.5,
            activeTrackColor: _vlcOrange,
            inactiveTrackColor: Colors.white24,
            thumbColor: _vlcOrange,
            overlayColor: _vlcOrange.withValues(alpha: 0.16),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
          ),
          child: Slider(
            value: value,
            onChanged: (next) {
              final target = Duration(
                milliseconds: (duration.inMilliseconds * next).round(),
              );
              onSeek(target);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Text(
                _formatPlaybackTime(position),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Text(
                _formatPlaybackTime(duration),
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AndroidLivePill extends StatelessWidget {
  const _AndroidLivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _vlcOrange.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _vlcOrange.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: _vlcOrange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'EN VIVO',
            style: TextStyle(
              color: _vlcOrange,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}

class _AndroidIconButton extends StatelessWidget {
  const _AndroidIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 42,
    this.iconSize = 22,
    this.active = false,
    this.accent,
    this.filled = false,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final bool active;
  final Color? accent;
  final bool filled;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final accentColor = accent ?? _vlcOrange;
    return Semantics(
      button: true,
      label: label,
      child: NexusFocusable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        focusedScale: 1.06,
        semanticLabel: label,
        builder: (context, focused, hovered) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary
                  ? accentColor
                  : active
                  ? accentColor.withValues(alpha: 0.16)
                  : (filled
                        ? Colors.black.withValues(alpha: hovered ? 0.6 : 0.42)
                        : Colors.white.withValues(
                            alpha: hovered ? 0.10 : 0.03,
                          )),
              border: Border.all(
                color: focused
                    ? accentColor
                    : primary
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.08),
                width: focused ? 1.6 : 1,
              ),
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: primary
                  ? Colors.black
                  : active
                  ? accentColor
                  : Colors.white,
            ),
          );
        },
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
      leading: Icon(icon, color: accent ?? Colors.white70, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: accent ?? Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.channel,
    required this.isFavorite,
    required this.quality,
    required this.hasError,
    required this.onBack,
    required this.onToggleFavorite,
    required this.onFullscreen,
    required this.fullscreen,
  });

  final Channel channel;
  final bool isFavorite;
  final String? quality;
  final bool hasError;
  final VoidCallback onBack;
  final VoidCallback onToggleFavorite;
  final VoidCallback onFullscreen;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 36),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xE6000000), Color(0x99000000), Colors.transparent],
          stops: [0, 0.62, 1],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            _GlassButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Volver',
              onTap: onBack,
            ),
            const SizedBox(width: 10),
            ChannelLogo(channel: channel, width: 52, height: 38, radius: 8),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasError
                              ? AppColors.danger
                              : AppColors.success,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (hasError
                                          ? AppColors.danger
                                          : AppColors.success)
                                      .withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        channel.isVod ? 'A LA CARTA' : 'EN VIVO',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          channel.group,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                      if (quality != null) ...[
                        const SizedBox(width: 8),
                        _QualityChip(label: quality!),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _GlassButton(
              icon: isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              tooltip: isFavorite
                  ? 'Quitar de favoritos'
                  : 'Añadir a favoritos',
              activeColor: const Color(0xFFFB7185),
              active: isFavorite,
              onTap: onToggleFavorite,
            ),
            const SizedBox(width: 6),
            _GlassButton(
              icon: fullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              tooltip: fullscreen
                  ? 'Salir de pantalla completa'
                  : 'Pantalla completa',
              onTap: onFullscreen,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.channel,
    required this.playing,
    required this.volume,
    required this.quality,
    required this.isTv,
    required this.playFocus,
    required this.fullscreen,
    required this.position,
    required this.duration,
    required this.showAudioPicker,
    required this.showSubtitlePicker,
    required this.audioActive,
    required this.subtitleActive,
    required this.onAudio,
    required this.onSubtitle,
    required this.onPlayPause,
    required this.onToggleMute,
    required this.onVolumeChanged,
    required this.onOpenChannels,
    required this.onFullscreen,
    required this.onSeek,
  });

  final Channel channel;
  final bool playing;
  final double volume;
  final String? quality;
  final bool isTv;
  final FocusNode playFocus;
  final bool fullscreen;
  final Duration position;
  final Duration duration;
  final bool showAudioPicker;
  final bool showSubtitlePicker;
  final bool audioActive;
  final bool subtitleActive;
  final VoidCallback onAudio;
  final VoidCallback onSubtitle;
  final VoidCallback onPlayPause;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onOpenChannels;
  final VoidCallback onFullscreen;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final isVod = channel.isVod && duration.inMilliseconds > 0;
    return Container(
      padding: const EdgeInsets.only(top: 44),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF2000000), Color(0xA6000000), Colors.transparent],
          stops: [0, 0.58, 1],
        ),
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 640;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isVod)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: _ProgressBar(
                      position: position,
                      duration: duration,
                      onSeek: onSeek,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Row(
                    children: [
                      _GlassButton(
                        focusNode: playFocus,
                        icon: playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        tooltip: playing ? 'Pausar' : 'Reproducir',
                        onTap: onPlayPause,
                        size: 46,
                        iconSize: 24,
                      ),
                      const SizedBox(width: 4),
                      _GlassButton(
                        icon: volume == 0
                            ? Icons.volume_off_rounded
                            : (volume < 50
                                  ? Icons.volume_down_rounded
                                  : Icons.volume_up_rounded),
                        tooltip: volume == 0 ? 'Activar sonido' : 'Silenciar',
                        onTap: onToggleMute,
                      ),
                      if (wide) ...[
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 140,
                          child: _VolumeSlider(
                            volume: volume,
                            onChanged: onVolumeChanged,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(width: 2),
                        Expanded(
                          child: _VolumeSlider(
                            volume: volume,
                            onChanged: onVolumeChanged,
                          ),
                        ),
                      ],
                      if (showAudioPicker) ...[
                        const SizedBox(width: 2),
                        _GlassButton(
                          icon: Icons.audiotrack_rounded,
                          tooltip: 'Idioma de audio',
                          onTap: onAudio,
                          active: audioActive,
                          size: 36,
                          iconSize: 18,
                        ),
                      ],
                      if (showSubtitlePicker) ...[
                        const SizedBox(width: 2),
                        _GlassButton(
                          icon: Icons.subtitles_rounded,
                          tooltip: 'Subtítulos',
                          onTap: onSubtitle,
                          active: subtitleActive,
                          size: 36,
                          iconSize: 18,
                        ),
                      ],
                      if (wide) ...[
                        const SizedBox(width: 10),
                        if (isVod)
                          _TimeLabel(position: position, duration: duration)
                        else
                          const _LivePill(),
                        if (quality != null) ...[
                          const SizedBox(width: 6),
                          _QualityChip(label: quality!),
                        ],
                        const Spacer(),
                        if (!isTv)
                          const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Text(
                              'Espacio  ·  F  ·  M  ·  C',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 9.5,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        _GlassPillButton(
                          icon: Icons.playlist_play_rounded,
                          label: 'Canales',
                          tooltip: 'Cambiar de canal',
                          onTap: onOpenChannels,
                        ),
                      ] else
                        _GlassButton(
                          icon: Icons.playlist_play_rounded,
                          tooltip: 'Cambiar de canal',
                          onTap: onOpenChannels,
                        ),
                      const SizedBox(width: 4),
                      _GlassButton(
                        icon: fullscreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        tooltip: fullscreen
                            ? 'Salir de pantalla completa'
                            : 'Pantalla completa',
                        onTap: onFullscreen,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({required this.volume, required this.onChanged});

  final double volume;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        activeTrackColor: AppColors.cyan,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
        overlayColor: AppColors.cyan.withValues(alpha: 0.16),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      child: Slider(
        value: volume.clamp(0, 100),
        min: 0,
        max: 100,
        onChanged: onChanged,
      ),
    );
  }
}

class _BufferingOverlay extends StatelessWidget {
  const _BufferingOverlay({
    required this.channel,
    required this.reconnecting,
    required this.attempt,
    required this.loading,
  });

  final Channel channel;
  final bool reconnecting;
  final int attempt;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final title = reconnecting
        ? 'Reconectando señal…'
        : (loading ? 'Cargando señal…' : 'Estabilizando señal…');
    final detail = reconnecting
        ? 'Intento $attempt de ${PlayerTuning.maxRetries} · ${channel.name}'
        : channel.name;

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.38),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NeonSpinner(size: reconnecting ? 62 : 56),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aviso discreto de señal perdida tras agotar los reintentos.
///
/// No bloquea la imagen ni usa diálogos rojos del sistema: es una tarjeta
/// flotante con la identidad de la marca y acciones rápidas.
class _SignalLostBanner extends StatelessWidget {
  const _SignalLostBanner({
    required this.message,
    required this.channel,
    required this.onRetry,
    required this.onOpenChannels,
  });

  final String message;
  final Channel channel;
  final VoidCallback onRetry;
  final VoidCallback onOpenChannels;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 440;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 104,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.cyan.withValues(alpha: 0.24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.10),
                    blurRadius: 30,
                    spreadRadius: -6,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.cyan.withValues(alpha: 0.10),
                      border: Border.all(
                        color: AppColors.cyan.withValues(alpha: 0.26),
                      ),
                    ),
                    child: Icon(
                      Icons.wifi_tethering_off_rounded,
                      color: AppColors.cyan,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Señal interrumpida',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.cyan,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (compact)
                    IconButton(
                      tooltip: 'Reintentar',
                      onPressed: onRetry,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.refresh_rounded,
                        size: 20,
                        color: AppColors.cyan,
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text('Reintentar'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.cyan,
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Cambiar de canal',
                    onPressed: onOpenChannels,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.playlist_play_rounded,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controles reutilizables
// ---------------------------------------------------------------------------

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 40,
    this.iconSize = 21,
    this.active = false,
    this.activeColor,
    this.focusNode,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final bool active;
  final Color? activeColor;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final accentColor = activeColor ?? AppColors.accent;
    return Tooltip(
      message: tooltip,
      child: NexusFocusable(
        focusNode: focusNode,
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        focusedScale: 1.08,
        semanticLabel: tooltip,
        builder: (context, focused, hovered) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: focused
                  ? AppColors.cyan.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: hovered ? 0.58 : 0.42),
              border: Border.all(
                color: focused
                    ? AppColors.cyan
                    : Colors.white.withValues(alpha: 0.12),
                width: focused ? 1.6 : 1,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: AppColors.cyan.withValues(alpha: 0.3),
                        blurRadius: 18,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: active ? accentColor : Colors.white,
            ),
          );
        },
      ),
    );
  }
}

class _GlassPillButton extends StatelessWidget {
  const _GlassPillButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NexusFocusable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      focusedScale: 1.05,
      semanticLabel: tooltip,
      builder: (context, focused, hovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: focused
                ? AppColors.cyan.withValues(alpha: 0.18)
                : Colors.black.withValues(alpha: hovered ? 0.55 : 0.4),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: focused
                  ? AppColors.cyan
                  : Colors.white.withValues(alpha: 0.12),
              width: focused ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFFFB7185),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'EN VIVO',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Selector de canales
// ---------------------------------------------------------------------------

class ChannelPickerDialog extends StatefulWidget {
  const ChannelPickerDialog({
    super.key,
    required this.channels,
    required this.current,
  });

  final List<Channel> channels;
  final Channel current;

  @override
  State<ChannelPickerDialog> createState() => _ChannelPickerDialogState();
}

class _ChannelPickerDialogState extends State<ChannelPickerDialog> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final needle = _query.trim().toLowerCase();
    final filtered = needle.isEmpty
        ? widget.channels
        : widget.channels
              .where((channel) => channel.searchIndex.contains(needle))
              .toList(growable: false);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: AppColors.brandGradient,
                    ),
                    child: Icon(
                      Icons.playlist_play_rounded,
                      color: AppColors.onAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cambiar de canal',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${formatNumber(filtered.length)} de '
                          '${formatNumber(widget.channels.length)} canales',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ChannelSearchField(
                controller: _controller,
                autofocus: false,
                hint: 'Buscar en la lista completa…',
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay canales que coincidan con la búsqueda.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final channel = filtered[index];
                        final current = channel.url == widget.current.url;
                        final favorite = app.isFavorite(channel);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: NexusFocusable(
                            onTap: () => Navigator.of(context).pop(channel),
                            borderRadius: BorderRadius.circular(12),
                            focusedScale: 1.0,
                            semanticLabel: '${channel.name}, ${channel.group}',
                            builder: (context, focused, hovered) {
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 130),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: current
                                      ? AppColors.cyan.withValues(alpha: 0.09)
                                      : (focused
                                            ? AppColors.surfaceHighlight
                                            : (hovered
                                                  ? AppColors.surfaceHighlight
                                                        .withValues(alpha: 0.6)
                                                  : Colors.transparent)),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: focused
                                        ? AppColors.cyan
                                        : current
                                        ? AppColors.cyan.withValues(alpha: 0.3)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    ChannelLogo(
                                      channel: channel,
                                      width: 52,
                                      height: 42,
                                      radius: 8,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            channel.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: current
                                                  ? AppColors.cyan
                                                  : AppColors.textPrimary,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            channel.group,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (favorite)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 6),
                                        child: Icon(
                                          Icons.favorite_rounded,
                                          size: 13,
                                          color: Color(0xFFFB7185),
                                        ),
                                      ),
                                    if (current)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.cyan.withValues(
                                            alpha: 0.14,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                        ),
                                        child: Text(
                                          'EN PANTALLA',
                                          style: TextStyle(
                                            color: AppColors.cyan,
                                            fontSize: 7.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackPickerDialog<T> extends StatelessWidget {
  const _TrackPickerDialog({
    required this.title,
    required this.icon,
    required this.tracks,
    required this.selectedId,
    required this.idOf,
    required this.labelOf,
    required this.detailOf,
  });

  final String title;
  final IconData icon;
  final List<T> tracks;
  final String selectedId;
  final String Function(T) idOf;
  final String Function(T) labelOf;
  final String Function(T) detailOf;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = tracks.indexWhere(
      (track) => idOf(track) == selectedId,
    );
    final autofocusIndex = selectedIndex >= 0 ? selectedIndex : 0;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: AppColors.brandGradient,
                    ),
                    child: Icon(icon, color: AppColors.onAccent, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Elige la pista que quieres escuchar o leer.',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(10),
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  final selected = idOf(track) == selectedId;
                  final detail = detailOf(track);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: NexusFocusable(
                      autofocus: index == autofocusIndex,
                      onTap: () => Navigator.of(context).pop(track),
                      borderRadius: BorderRadius.circular(12),
                      focusedScale: 1.0,
                      semanticLabel: labelOf(track),
                      builder: (context, focused, hovered) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 130),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.accent.withValues(alpha: 0.10)
                                : (focused || hovered
                                      ? AppColors.surfaceHighlight
                                      : Colors.transparent),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: focused
                                  ? AppColors.accent
                                  : selected
                                  ? AppColors.accent.withValues(alpha: 0.34)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                size: 19,
                                color: selected
                                    ? AppColors.accent
                                    : AppColors.textFaint,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      labelOf(track),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected
                                            ? AppColors.accent
                                            : AppColors.textPrimary,
                                        fontSize: 13,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                      ),
                                    ),
                                    if (detail.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        detail,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final value = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        activeTrackColor: AppColors.cyan,
        inactiveTrackColor: Colors.white24,
        thumbColor: AppColors.cyan,
        overlayColor: AppColors.cyan.withValues(alpha: 0.2),
      ),
      child: Slider(
        value: value.clamp(0.0, 1.0),
        onChanged: (newValue) {
          final target = Duration(
            milliseconds: (duration.inMilliseconds * newValue).round(),
          );
          onSeek(target);
        },
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final elapsed = _formatDuration(position);
    final total = _formatDuration(duration);
    return Text(
      '$elapsed / $total',
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
