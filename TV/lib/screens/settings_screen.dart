import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/accent_theme.dart';
import '../core/app_layout.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../core/seasonal_theme.dart';
import '../services/proxy_service.dart';
import '../services/vpn_service.dart';
import '../state/app_state.dart';
import '../widgets/brand.dart';
import '../widgets/feedback.dart';
import '../widgets/nexus_focusable.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.layout});

  final AppLayout layout;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    final appearance = _SettingsCard(
      icon: Icons.palette_rounded,
      title: 'Apariencia',
      subtitle: 'Elige cómo quieres navegar por NexusStream.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ModeSelector(app: app),
          const SizedBox(height: 14),
          Text(
            app.modePreference == UiModePreference.auto
                ? 'Detección automática activa: ${app.layout.label}.'
                : 'Modo forzado: ${app.modePreference.label}.',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          const Text(
            'Fondo de pantalla',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Temporadas automáticas según la fecha o una imagen tuya. '
            'La imagen propia tiene prioridad.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          _SeasonSelector(app: app),
          const SizedBox(height: 12),
          _SeasonPreview(app: app),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          const Text(
            'Color de énfasis',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Se aplica a botones, foco, filtros y elementos activos.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          _AccentSelector(app: app),
        ],
      ),
    );

    final content = _SettingsCard(
      icon: Icons.cloud_download_rounded,
      title: 'Contenido',
      subtitle: app.useWiwy
          ? 'Servidor de canales: los tokens se renuevan solos.'
          : 'Lista M3U oficial de IPTV-Org.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Usar servidor de canales',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Activa canales y renueva credenciales desde el equipo, '
                      'sin emulador ni pasos manuales.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: app.useWiwy,
                onChanged: app.canUseWiwy
                    ? (value) => unawaited(app.setUseWiwy(value))
                    : null,
              ),
            ],
          ),
          const Divider(height: 22),
          _InfoRow(
            label: 'Fuente',
            value: app.sourceLabel,
            trailing: app.useWiwy
                ? null
                : IconButton(
                    tooltip: 'Copiar enlace',
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: app.sourceUrl),
                      );
                      if (context.mounted) {
                        showAppSnackBar(
                          context,
                          'Enlace de la lista copiado',
                          icon: Icons.link_rounded,
                        );
                      }
                    },
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                  ),
          ),
          if (app.useWiwy) ...[
            const SizedBox(height: 12),
            _InfoRow(
              label: 'Credenciales',
              value: app.wiwyAuthExpiry == null
                  ? 'pendientes de renovar'
                  : 'caducan ${formatUntil(app.wiwyAuthExpiry)} · '
                        '${formatClock(app.wiwyAuthExpiry)}',
            ),
            const SizedBox(height: 12),
            const _InfoRow(
              label: 'Renovación',
              value: 'automática en segundo plano',
            ),
          ],
          const Divider(height: 22),
          _InfoRow(
            label: 'Canales',
            value: '${formatNumber(app.channels.length)} disponibles',
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Categorías',
            value: '${formatNumber(app.categories.length)} grupos',
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Última actualización',
            value:
                '${formatRelative(app.lastUpdated)} · '
                '${formatClock(app.lastUpdated)}',
          ),
          if (app.hasError) ...[
            const SizedBox(height: 14),
            InlineErrorBanner(
              message: app.errorMessage!,
              onRetry: () => unawaited(app.refresh(silent: true)),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: app.isRefreshing ? null : () => _refresh(context, app),
              icon: app.isRefreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(
                app.isRefreshing ? 'Actualizando lista…' : 'Actualizar ahora',
              ),
            ),
          ),
        ],
      ),
    );

    final vpn = _SettingsCard(
      icon: Icons.vpn_lock_rounded,
      title: 'VPN / Proxy',
      subtitle: 'Sal por otro país para ver el catálogo sin restricciones.',
      child: _ProxyControl(app: app),
    );

    final favorites = _SettingsCard(
      icon: Icons.favorite_rounded,
      title: 'Favoritos',
      subtitle: 'Los canales que guardaste en este dispositivo.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GradientText(
                formatNumber(app.favoritesCount),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'canales guardados',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: app.favoritesCount == 0
                  ? null
                  : () => _confirmClearFavorites(context, app),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFDA4AF),
                side: BorderSide(
                  color: const Color(0xFFFB7185).withValues(alpha: 0.35),
                ),
              ),
              icon: const Icon(Icons.delete_sweep_rounded, size: 17),
              label: const Text('Borrar todos los favoritos'),
            ),
          ),
        ],
      ),
    );

    final playback = _SettingsCard(
      icon: Icons.movie_filter_rounded,
      title: 'Reproducción',
      subtitle: 'Motor multimedia de alto rendimiento.',
      child: Column(
        children: [
          const _InfoRow(label: 'Motor', value: 'media_kit · libmpv'),
          const SizedBox(height: 12),
          const _InfoRow(
            label: 'Formatos',
            value: 'HLS · DASH · MP4 · RTMP · TS',
          ),
          const SizedBox(height: 12),
          const _InfoRow(
            label: 'Pantalla completa',
            value: 'Botón dedicado o tecla F',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cyan.withValues(alpha: 0.14)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.bolt_rounded, size: 16, color: AppColors.cyan),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Decodificación por hardware, controles de volumen y '
                    'selector de canales integrados.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final about = _SettingsCard(
      icon: Icons.info_outline_rounded,
      title: 'Acerca de',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandBanner(height: 62),
          const SizedBox(height: 14),
          const Text(
            'NexusStream es un reproductor IPTV multiplataforma construido '
            'con Flutter. La lista de canales proviene del proyecto abierto '
            'IPTV-Org.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Tag(label: 'v1.0.0'),
              const SizedBox(width: 8),
              _Tag(label: app.layout.label),
              const SizedBox(width: 8),
              const _Tag(label: 'Flutter'),
            ],
          ),
        ],
      ),
    );

    final cards = layout.isDesktop
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    appearance,
                    const SizedBox(height: 18),
                    playback,
                    const SizedBox(height: 18),
                    about,
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  children: [
                    content,
                    const SizedBox(height: 18),
                    vpn,
                    const SizedBox(height: 18),
                    favorites,
                  ],
                ),
              ),
            ],
          )
        : Column(
            children: [
              appearance,
              const SizedBox(height: 16),
              content,
              const SizedBox(height: 16),
              vpn,
              const SizedBox(height: 16),
              favorites,
              const SizedBox(height: 16),
              playback,
              const SizedBox(height: 16),
              about,
            ],
          );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        layout.pagePadding,
        layout.isPhone ? 14 : 24,
        layout.pagePadding,
        28,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ajustes',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Personaliza la interfaz y administra tu contenido.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.devices_rounded,
                          size: 13,
                          color: AppColors.cyan,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          layout.label,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              cards,
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  'NexusStream · IPTV Player · Hecho con Flutter',
                  style: TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 10.5,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh(BuildContext context, AppState app) async {
    await app.refresh(silent: true);
    if (!context.mounted) return;
    if (app.errorMessage != null) {
      showAppSnackBar(
        context,
        app.errorMessage!,
        icon: Icons.cloud_off_rounded,
      );
    } else {
      showAppSnackBar(
        context,
        'Lista actualizada: ${formatNumber(app.channels.length)} canales',
        icon: Icons.check_circle_rounded,
      );
    }
  }

  Future<void> _confirmClearFavorites(
    BuildContext context,
    AppState app,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('¿Borrar todos los favoritos?'),
          content: const Text(
            'Se eliminarán todos los canales guardados en este dispositivo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE11D48),
              ),
              child: const Text('Borrar'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      app.clearFavorites();
      if (context.mounted) {
        showAppSnackBar(
          context,
          'Favoritos eliminados',
          icon: Icons.delete_outline_rounded,
        );
      }
    }
  }
}

class _ProxyControl extends StatefulWidget {
  const _ProxyControl({required this.app});

  final AppState app;

  @override
  State<_ProxyControl> createState() => _ProxyControlState();
}

class _ProxyControlState extends State<_ProxyControl> {
  ProxyTestResult? _result;
  bool _testing = false;
  bool _busy = false;

  bool get _android => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    VpnService.instance.addListener(_onVpnChanged);
    if (widget.app.proxyEnabled) unawaited(_test());
  }

  @override
  void dispose() {
    VpnService.instance.removeListener(_onVpnChanged);
    super.dispose();
  }

  void _onVpnChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    final result = await ProxySettings.instance.test();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = result;
    });
    debugPrint('VPN prueba: ${result.summary}');
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _busy = true;
      _result = null;
    });
    await widget.app.setProxyEnabled(value);
    if (!mounted) return;
    setState(() => _busy = false);
    if (value) unawaited(_test());
  }

  Future<void> _edit() async {
    final value = await showDialog<({String host, int port})>(
      context: context,
      builder: (context) =>
          _ProxyDialog(host: widget.app.proxyHost, port: widget.app.proxyPort),
    );
    if (value == null) return;

    await widget.app.setProxyEndpoint(value.host, value.port);
    if (!mounted) return;
    setState(() => _result = null);
    if (widget.app.proxyEnabled) unawaited(_test());
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Activar VPN',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Portal, catálogo y reproducción salen por la VPN.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: app.proxyEnabled,
              onChanged: _busy ? null : (value) => unawaited(_toggle(value)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_android)
          _InfoRow(label: 'Perfil', value: VpnService.instance.profileLabel)
        else
          _InfoRow(
            label: 'Servidor',
            value: app.proxyAuthority,
            trailing: IconButton(
              tooltip: 'Cambiar servidor',
              onPressed: _edit,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_rounded, size: 16),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            _statusIcon(),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _statusText(app),
                style: TextStyle(
                  color: _statusColor(),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
            TextButton(
              onPressed: _testing || _busy ? null : () => unawaited(_test()),
              child: Text(_testing || _busy ? 'Comprobando…' : 'Probar'),
            ),
          ],
        ),
        if (app.proxyEnabled) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFB7185).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFFB7185).withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: Color(0xFFFB7185),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _android
                        ? 'Android pedirá permiso de VPN la primera vez; '
                              'acéptalo para que el túnel funcione. Si el '
                              'servidor Netxxus no responde, la app prueba '
                              'sola el perfil de respaldo.'
                        : 'Si el proxy no responde, el portal y los canales '
                              'dejarán de cargar. Desactívalo para volver a '
                              'la conexión directa.',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _statusText(AppState app) {
    if (_android) return VpnService.instance.statusLabel;
    if (_testing) return 'Comprobando conexión…';
    final result = _result;
    if (result != null) return result.summary;
    return app.proxyEnabled ? 'Sin comprobar' : 'Conexión directa';
  }

  Widget _statusIcon() {
    if (_android) {
      final phase = VpnService.instance.phase;
      if (phase == VpnPhase.connecting) {
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      }
      return Icon(_vpnIcon(phase), size: 15, color: _statusColor());
    }
    if (_testing) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final result = _result;
    if (result == null) {
      return const Icon(
        Icons.link_rounded,
        size: 15,
        color: AppColors.textMuted,
      );
    }
    return Icon(
      result.ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
      size: 15,
      color: _statusColor(),
    );
  }

  IconData _vpnIcon(VpnPhase phase) {
    switch (phase) {
      case VpnPhase.connected:
        return Icons.check_circle_rounded;
      case VpnPhase.denied:
      case VpnPhase.failed:
        return Icons.error_outline_rounded;
      case VpnPhase.connecting:
        return Icons.sync_rounded;
      case VpnPhase.idle:
      case VpnPhase.unavailable:
        return Icons.link_rounded;
    }
  }

  Color _statusColor() {
    if (_android) {
      switch (VpnService.instance.phase) {
        case VpnPhase.connected:
          return const Color(0xFF4ADE80);
        case VpnPhase.denied:
        case VpnPhase.failed:
          return const Color(0xFFFB7185);
        case VpnPhase.connecting:
        case VpnPhase.idle:
        case VpnPhase.unavailable:
          return AppColors.textMuted;
      }
    }
    if (_testing) return AppColors.textMuted;
    final result = _result;
    if (result == null) return AppColors.textMuted;
    return result.ok ? const Color(0xFF4ADE80) : const Color(0xFFFB7185);
  }
}

class _ProxyDialog extends StatefulWidget {
  const _ProxyDialog({required this.host, required this.port});

  final String host;
  final int port;

  @override
  State<_ProxyDialog> createState() => _ProxyDialogState();
}

class _ProxyDialogState extends State<_ProxyDialog> {
  late final TextEditingController _host = TextEditingController(
    text: widget.host,
  );
  late final TextEditingController _port = TextEditingController(
    text: '${widget.port}',
  );
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _save() {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 0;
    if (host.isEmpty || port <= 0 || port > 65535) {
      setState(() => _error = 'Escribe un host y un puerto válidos.');
      return;
    }
    Navigator.of(context).pop((host: host, port: port));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Servidor del proxy'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _host,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Host o IP',
              hintText: '154.62.127.162',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'Puerto',
              hintText: '999',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFFB7185), fontSize: 11.5),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0C172B), Color(0xFF091120)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    colors: [
                      AppColors.cyan.withValues(alpha: 0.16),
                      AppColors.violet.withValues(alpha: 0.12),
                    ],
                  ),
                  border: Border.all(
                    color: AppColors.cyan.withValues(alpha: 0.18),
                  ),
                ),
                child: Icon(icon, size: 18, color: AppColors.cyan),
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
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 4), trailing!],
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mode in UiModePreference.values)
          NexusFocusable(
            onTap: () => app.setModePreference(mode),
            borderRadius: BorderRadius.circular(10),
            focusedScale: 1.03,
            semanticLabel: mode.label,
            builder: (context, focused, hovered) {
              final selected = app.modePreference == mode;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  gradient: selected ? AppColors.brandGradientHorizontal : null,
                  color: selected
                      ? null
                      : (hovered
                            ? AppColors.surfaceHighlight
                            : AppColors.surface),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: focused
                        ? AppColors.cyan
                        : selected
                        ? Colors.transparent
                        : AppColors.border,
                    width: focused ? 1.5 : 1,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: AppColors.cyan.withValues(alpha: 0.25),
                            blurRadius: 16,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      mode.icon,
                      size: 15,
                      color: selected
                          ? AppColors.onAccent
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      mode.label,
                      style: TextStyle(
                        color: selected
                            ? AppColors.onAccent
                            : AppColors.textPrimary,
                        fontSize: 11.5,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _SeasonSelector extends StatelessWidget {
  const _SeasonSelector({required this.app});

  final AppState app;

  Future<void> _pickWallpaper(BuildContext context) async {
    final saved = await app.pickCustomWallpaper();
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      saved ? 'Imagen de fondo actualizada' : 'No se eligió ninguna imagen',
      icon: saved ? Icons.image_rounded : Icons.info_outline_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final customActive = app.customWallpaperPath != null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final theme in SeasonalTheme.values)
          _SeasonChip(
            icon: theme.icon,
            label: theme.label,
            selected: !customActive && app.seasonalThemePreference == theme,
            onTap: () => app.setSeasonalTheme(theme),
          ),
        _SeasonChip(
          icon: Icons.image_rounded,
          label: 'Mi imagen',
          selected: customActive,
          onTap: () => unawaited(_pickWallpaper(context)),
        ),
      ],
    );
  }
}

class _SeasonChip extends StatelessWidget {
  const _SeasonChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NexusFocusable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      focusedScale: 1.03,
      semanticLabel: label,
      builder: (context, focused, hovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.brandGradientHorizontal : null,
            color: selected
                ? null
                : (hovered ? AppColors.surfaceHighlight : AppColors.surface),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: focused
                  ? AppColors.cyan
                  : selected
                  ? Colors.transparent
                  : AppColors.border,
              width: focused ? 1.5 : 1,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: AppColors.cyan.withValues(alpha: 0.25),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? AppColors.onAccent : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.onAccent : AppColors.textPrimary,
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Miniatura del fondo que se está mostrando y controles para cambiarlo.
class _SeasonPreview extends StatelessWidget {
  const _SeasonPreview({required this.app});

  final AppState app;

  Future<void> _pick(BuildContext context) async {
    final saved = await app.pickCustomWallpaper();
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      saved ? 'Imagen de fondo actualizada' : 'No se eligió ninguna imagen',
      icon: saved ? Icons.image_rounded : Icons.info_outline_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final custom = app.customWallpaperPath;
    final active = app.seasonalTheme;
    final wallpaper = active.asset(phone: app.layout.isPhone);
    final automatic = app.seasonalThemePreference == SeasonalTheme.auto;

    final message = switch (active) {
      _ when custom != null =>
        'Imagen propia activa. Tiene prioridad sobre '
            'la temporada.',
      SeasonalTheme.none =>
        automatic
            ? 'Hoy no toca ningún fondo estacional.'
            : 'Fondo estacional desactivado.',
      _ when automatic => 'Automático: hoy se muestra ${active.label}.',
      _ => 'Fondo fijo: ${active.label}.',
    };

    Widget thumbnail() {
      if (custom != null) {
        return Image.file(
          File(custom),
          key: ValueKey(custom),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const _EmptyWallpaper(),
        );
      }
      if (wallpaper == null) return const _EmptyWallpaper();
      return Image.asset(
        wallpaper,
        key: ValueKey(wallpaper),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _EmptyWallpaper(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(width: 88, height: 50, child: thumbnail()),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: () => unawaited(_pick(context)),
              icon: const Icon(Icons.folder_open_rounded, size: 16),
              label: Text(custom == null ? 'Elegir imagen…' : 'Cambiar imagen'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
                side: const BorderSide(color: AppColors.borderStrong),
              ),
            ),
            if (custom != null)
              TextButton.icon(
                onPressed: () => unawaited(app.clearCustomWallpaper()),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Quitar imagen'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  foregroundColor: AppColors.textMuted,
                  textStyle: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _EmptyWallpaper extends StatelessWidget {
  const _EmptyWallpaper();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surface,
      child: Icon(
        Icons.hide_image_rounded,
        size: 20,
        color: AppColors.textFaint,
      ),
    );
  }
}

class _AccentSelector extends StatelessWidget {
  const _AccentSelector({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final accent in AppAccent.all)
              Tooltip(
                message: accent.label,
                child: NexusFocusable(
                  onTap: () => unawaited(app.setAccent(accent)),
                  borderRadius: BorderRadius.circular(99),
                  focusedScale: 1.08,
                  semanticLabel: 'Énfasis ${accent.label}',
                  builder: (context, focused, hovered) {
                    final selected = app.accent.id == accent.id;
                    final onColor = accent.color.computeLuminance() > 0.55
                        ? const Color(0xFF101114)
                        : Colors.white;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accent.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? Colors.white
                              : focused
                              ? AppColors.accent
                              : Colors.white.withValues(alpha: 0.14),
                          width: selected ? 2.5 : (focused ? 2 : 1),
                        ),
                        boxShadow: selected || focused
                            ? [
                                BoxShadow(
                                  color: accent.color.withValues(
                                    alpha: selected ? 0.45 : 0.3,
                                  ),
                                  blurRadius: 14,
                                ),
                              ]
                            : null,
                      ),
                      child: selected
                          ? Icon(Icons.check_rounded, size: 19, color: onColor)
                          : null,
                    );
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Énfasis actual: ${app.accent.label}',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 10.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
