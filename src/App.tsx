import { For, Show, onCleanup, onMount, type Component, type JSX } from 'solid-js';
import { createEffect, createSignal } from 'solid-js';
import { downloadUrl, formatBytes, manifest, type DownloadInfo } from './downloads';

type DownloadKind = 'windows' | 'android' | 'linux';

const DOWNLOAD_KINDS: DownloadKind[] = ['windows', 'android', 'linux'];

const NAV_LINKS = [
  { href: '#caracteristicas', label: 'Características' },
  { href: '#capturas', label: 'Capturas' },
  { href: '#plataformas', label: 'Plataformas' },
  { href: '#descargar', label: 'Descargar' },
];

const SCREENS = [
  {
    src: '/screens/tv-en-vivo.png',
    title: 'TV en vivo',
    text: 'Más de 1.000 canales con reproductor integrado, favoritos y búsqueda.',
  },
  {
    src: '/screens/cine.png',
    title: 'Cine',
    text: 'Catálogo de películas, series e infantil con puntuaciones y pósters.',
  },
  {
    src: '/screens/ficha.png',
    title: 'Ficha completa',
    text: 'Sinopsis, reparto, dirección, duración y géneros de cada título.',
  },
  {
    src: '/screens/reproductor.png',
    title: 'Reproductor',
    text: 'Progreso, volumen, pista de audio y selección de canales al instante.',
  },
  {
    src: '/screens/ajustes.png',
    title: 'Ajustes',
    text: 'Apariencia, fondo estacional, portal y VPN integrada, todo en la app.',
  },
];

const FEATURES = [
  {
    title: 'TV en vivo',
    icon: '📡',
    text: 'Más de 1000 canales en directo organizados por categorías, con cambio de canal rápido y reconexión automática.',
  },
  {
    title: 'Películas y series',
    icon: '🎬',
    text: 'Catálogo completo de VOD con fichas, sinopsis, reparto y búsqueda global del portal.',
  },
  {
    title: 'Subtítulos incluidos',
    icon: '💬',
    text: 'Subtítulos en español y otros idiomas para películas y series, seleccionables desde el reproductor.',
  },
  {
    title: 'Navegación de TV',
    icon: '📺',
    text: 'Interfaz pensada para el control remoto: foco visible, rejillas amplias y atajos de teclado en el PC.',
  },
  {
    title: 'VPN integrada',
    icon: '🔐',
    text: 'En Android, OpenVPN nativo con perfil principal y de respaldo. En Windows, proxy HTTP configurable.',
  },
  {
    title: 'Varios equipos a la vez',
    icon: '📱',
    text: 'Android, Android TV, Windows y Linux en paralelo: cada instalación tiene su propia identidad y ninguna cierra la sesión de la otra.',
  },
  {
    title: 'Listo al abrir',
    icon: '✅',
    text: 'Sin cuentas ni códigos: la app se registra sola la primera vez y recuerda su identidad en los siguientes arranques.',
  },
  {
    title: 'Portable',
    icon: '🧳',
    text: 'La misma app para televisor, móvil y escritorio, con instalación en un clic y sin dependencias extra.',
  },
  {
    title: 'Caché inteligente',
    icon: '⚡',
    text: 'Arranca al instante con la caché local y renueva credenciales en segundo plano, sin cortes para ti.',
  },
];

const WindowsIcon: Component<{ class?: string }> = (props) => (
  <svg viewBox="0 0 24 24" fill="currentColor" class={props.class} aria-hidden="true">
    <path d="M3 5.5 10.5 4.4v7.1H3V5.5Zm0 13 7.5 1.1v-7H3v5.9Zm8.5 1.2L21 21V12.5h-9.5v7.2Zm0-15.4v7.2H21V3l-9.5 1.3Z" />
  </svg>
);

const AndroidIcon: Component<{ class?: string }> = (props) => (
  <svg viewBox="0 0 24 24" fill="currentColor" class={props.class} aria-hidden="true">
    <path d="m17.6 9.48 1.84-3.18c.16-.31.04-.7-.26-.85-.29-.15-.65-.06-.83.22l-1.88 3.24a11.46 11.46 0 0 0-8.94 0L5.65 5.67a.61.61 0 0 0-.83-.22c-.3.15-.42.54-.26.85L6.4 9.48A10.78 10.78 0 0 0 1 18h22a10.78 10.78 0 0 0-5.4-8.52ZM7 15.25a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5Zm10 0a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5Z" />
  </svg>
);

const LinuxIcon: Component<{ class?: string }> = (props) => (
  <svg viewBox="0 0 24 24" fill="currentColor" class={props.class} aria-hidden="true">
    <path d="M12.2 2c-2.3 0-3.7 1.8-3.6 4.3.05 1.4.5 2.3.2 3.2-.3.9-1.3 1.8-2.1 3.1-.9 1.4-1.3 2.9-.6 4.2.4.8 1.2 1.2 2.1 1.3.7.1 1.3-.2 1.8-.7.5-.5.8-1.2 1.4-1.7.6-.5 1.4-.6 2.1-.3.6.3 1 1 1.6 1.4.5.4 1.2.5 1.8.2.8-.4 1.2-1.3 1.1-2.2-.1-1.2-.9-2.2-1.6-3.2-.7-1-1.3-1.9-1.4-3-.1-1.2.4-2.2.2-3.4C16.4 3.6 14.7 2 12.2 2Zm-.7 4.1a.9.9 0 1 1 0 1.8.9.9 0 0 1 0-1.8Zm2.7.1a.8.8 0 1 1 0 1.6.8.8 0 0 1 0-1.6Zm-3.2 4.8c.8.4 1.7.4 2.5.1-.2.6-.6 1-1.2 1.2-.6-.2-1-.6-1.3-1.3Z" />
  </svg>
);

const platformIcon = (kind: DownloadKind) => {
  if (kind === 'windows') return <WindowsIcon class="h-6 w-6" />;
  if (kind === 'linux') return <LinuxIcon class="h-6 w-6" />;
  return <AndroidIcon class="h-6 w-6" />;
};

const DownloadButton: Component<{
  info?: DownloadInfo;
  kind: DownloadKind;
  size?: 'lg' | 'md';
}> = (props) => {
  const href = () =>
    downloadUrl(props.info) ??
    (props.kind === 'windows'
      ? '/downloads/NexusStream-Setup-1.0.8.exe'
      : props.kind === 'linux'
        ? '/downloads/NexusStream-1.0.8-linux-x64.tar.gz'
        : '/downloads/NexusStream-1.0.8.apk');
  const label = () => {
    if (props.kind === 'windows') return 'Descargar para Windows';
    if (props.kind === 'linux') return 'Descargar para Linux';
    return 'Descargar para Android';
  };
  const meta = () => {
    const parts = [formatBytes(props.info?.bytes)];
    if (props.kind === 'windows') parts.push('Windows 10/11 · 64 bits');
    else if (props.kind === 'linux')
      parts.push('Linux x64 · glibc 2.35+ · tar.gz');
    else parts.push('Android 7.0+ · APK');
    return parts.filter(Boolean).join(' · ');
  };

  const base =
    'group inline-flex items-center gap-3 rounded-2xl px-6 py-4 font-semibold shadow-lg transition duration-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-400 focus-visible:ring-offset-2 focus-visible:ring-offset-night-950';
  const styles =
    props.kind === 'windows'
      ? `${base} bg-gradient-to-r from-brand-500 to-brand-600 text-white hover:from-brand-400 hover:to-brand-500 hover:shadow-brand-500/30`
      : props.kind === 'linux'
        ? `${base} border border-sky-400/30 bg-sky-500/10 text-white hover:border-sky-400/60 hover:bg-sky-500/20`
        : `${base} border border-white/15 bg-white/5 text-white hover:border-brand-400/60 hover:bg-white/10`;
  const sizeClass = props.size === 'lg' ? 'text-lg' : 'text-base';

  return (
    <Show
      when={href()}
      fallback={
        <span class={`${styles} ${sizeClass} pointer-events-none opacity-60`}>
          {platformIcon(props.kind)}
          {label()}
        </span>
      }
    >
      <a href={href()} download="" class={`${styles} ${sizeClass} hover:-translate-y-0.5`}>
        {platformIcon(props.kind)}
        <span class="flex flex-col items-start leading-tight">
          <span>{label()}</span>
          <span class="text-xs font-normal text-white/70 group-hover:text-white/90">
            {meta()}
          </span>
        </span>
      </a>
    </Show>
  );
};

const SectionTitle: Component<{ eyebrow: string; title: string; subtitle?: string }> = (
  props,
) => (
  <div class="mx-auto mb-12 max-w-2xl text-center">
    <p class="text-sm font-semibold uppercase tracking-widest text-brand-400">
      {props.eyebrow}
    </p>
    <h2 class="mt-2 text-3xl font-bold text-white sm:text-4xl">{props.title}</h2>
    <Show when={props.subtitle}>
      <p class="mt-3 text-slate-400">{props.subtitle}</p>
    </Show>
  </div>
);

const Navbar: Component = () => (
  <header class="sticky top-0 z-50 border-b border-white/5 bg-night-950/80 backdrop-blur">
    <nav class="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
      <a href="#inicio" class="flex items-center gap-3">
        <img src="/icon.png" alt="NexusStream" class="h-9 w-9 rounded-xl" />
        <span class="text-lg font-bold text-white">NexusStream</span>
      </a>
      <div class="hidden items-center gap-8 text-sm text-slate-300 sm:flex">
        <For each={NAV_LINKS}>
          {(link) => (
            <a href={link.href} class="transition hover:text-white">
              {link.label}
            </a>
          )}
        </For>
      </div>
      <a
        href="#descargar"
        class="rounded-xl bg-gradient-to-r from-brand-500 to-brand-600 px-4 py-2 text-sm font-semibold text-white transition hover:from-brand-400 hover:to-brand-500"
      >
        Descargar
      </a>
    </nav>
  </header>
);

const Hero: Component = () => (
  <section id="inicio" class="relative overflow-hidden">
    <div
      class="pointer-events-none absolute inset-0 bg-[radial-gradient(60%_50%_at_50%_0%,#12205466_0%,transparent_70%)]"
      aria-hidden="true"
    />
    <div class="mx-auto flex max-w-6xl flex-col items-center px-6 pb-20 pt-16 text-center sm:pt-24">
      <img
        src="/icon.png"
        alt="Logo de NexusStream"
        class="h-24 w-24 rounded-3xl shadow-2xl shadow-brand-600/40 ring-1 ring-white/10"
      />
      <h1 class="mt-8 max-w-3xl text-4xl font-extrabold leading-tight text-white sm:text-6xl">
        Tu TV, tus películas.
        <span class="bg-gradient-to-r from-brand-400 to-sky-300 bg-clip-text text-transparent">
          {' '}
          Donde quieras.
        </span>
      </h1>
      <p class="mt-5 max-w-2xl text-lg text-slate-400">
        NexusStream reúne la televisión en vivo y un catálogo de películas y
        series con subtítulos, en una sola app ligera y lista para tu
        televisor, tu móvil y tu PC.
      </p>
      <div class="mt-10 flex flex-col items-center gap-4 sm:flex-row">
        <DownloadButton info={manifest()?.windows} kind="windows" size="lg" />
        <DownloadButton info={manifest()?.android} kind="android" size="lg" />
        <DownloadButton info={manifest()?.linux} kind="linux" size="lg" />
      </div>
      <p class="mt-4 text-xs text-slate-500">
        Versión {manifest()?.version ?? '1.0.0'} · Gratis · Sin anuncios
      </p>
    </div>
  </section>
);

const Features: Component = () => (
  <section id="caracteristicas" class="border-y border-white/5 bg-night-900/60 py-20">
    <div class="mx-auto max-w-6xl px-6">
      <SectionTitle
        eyebrow="Características"
        title="Todo lo que buscas, en una app"
        subtitle="Diseñada para televisores y pantallas grandes, cómoda también en el móvil y el escritorio."
      />
      <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
        <For each={FEATURES}>
          {(feature) => (
            <div class="rounded-2xl border border-white/5 bg-night-800/60 p-6 transition duration-200 hover:-translate-y-1 hover:border-brand-500/40 hover:shadow-lg hover:shadow-brand-600/10">
              <div class="flex h-11 w-11 items-center justify-center rounded-xl bg-brand-500/10 text-2xl">
                {feature.icon}
              </div>
              <h3 class="mt-4 text-lg font-semibold text-white">{feature.title}</h3>
              <p class="mt-2 text-sm leading-relaxed text-slate-400">{feature.text}</p>
            </div>
          )}
        </For>
      </div>
    </div>
  </section>
);

const REQUIREMENTS = [
  {
    kind: 'windows' as const,
    title: 'Windows',
    requirements: [
      'Windows 10 o 11, 64 bits',
      '4 GB de RAM recomendados',
      'Conexión a internet de 5 Mbps o más',
      'Instalador con runtime de Visual C++ incluido',
    ],
  },
  {
    kind: 'android' as const,
    title: 'Android y Android TV',
    requirements: [
      'Android 7.0 o superior',
      'Compatible con TV Stick y televisores Android TV',
      'Permitir instalación de orígenes desconocidos',
      'VPN OpenVPN opcional integrada',
    ],
  },
  {
    kind: 'linux' as const,
    title: 'Linux',
    requirements: [
      'Ubuntu 22.04 o superior, x86-64',
      'Se extrae y se ejecuta sin root',
      'Instalador de usuario opcional incluido',
      'Requiere libmpv2 en el sistema',
    ],
  },
];

const Platforms: Component = () => (
  <section id="plataformas" class="py-20">
    <div class="mx-auto max-w-6xl px-6">
      <SectionTitle
        eyebrow="Plataformas"
        title="Elige tu plataforma"
        subtitle="La misma experiencia en el televisor del salón, el móvil y el PC."
      />
      <div class="grid gap-8 md:grid-cols-2 lg:grid-cols-3">
        <For each={REQUIREMENTS}>
          {(platform) => (
            <div class="rounded-3xl border border-white/5 bg-gradient-to-b from-night-800/80 to-night-900/80 p-8">
              <div class="flex items-center gap-4">
                <div class="flex h-12 w-12 items-center justify-center rounded-2xl bg-brand-500/15 text-brand-400">
                  {platformIcon(platform.kind)}
                </div>
                <h3 class="text-xl font-bold text-white">{platform.title}</h3>
              </div>
              <ul class="mt-6 space-y-3 text-sm text-slate-300">
                <For each={platform.requirements}>
                  {(item) => (
                    <li class="flex items-start gap-3">
                      <span class="mt-1 text-brand-400" aria-hidden="true">
                        ✓
                      </span>
                      <span>{item}</span>
                    </li>
                  )}
                </For>
              </ul>
              <div class="mt-8">
                <DownloadButton
                  info={manifest()?.[platform.kind]}
                  kind={platform.kind}
                />
              </div>
            </div>
          )}
        </For>
      </div>
    </div>
  </section>
);

const AUTOPLAY_MS = 3000;

const Screenshots: Component = () => {
  const n = SCREENS.length;
  const [index, setIndex] = createSignal(0);
  const [paused, setPaused] = createSignal(false);
  const [open, setOpen] = createSignal<string | null>(null);
  let barRef: HTMLSpanElement | undefined;

  const reduceMotion =
    typeof window !== 'undefined' &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  const go = (next: number) => setIndex(((next % n) + n) % n);

  onMount(() => {
    if (reduceMotion) return;
    const timer = setInterval(() => {
      if (!paused()) go(index() + 1);
    }, AUTOPLAY_MS);
    onCleanup(() => clearInterval(timer));
  });

  // Reinicia la barra de progreso cada vez que cambia la diapositiva
  createEffect(() => {
    index();
    if (barRef) {
      barRef.style.animation = 'none';
      void barRef.offsetWidth;
      barRef.style.animation = '';
    }
  });

  const onKey = (event: KeyboardEvent) => {
    if (event.key === 'Escape') setOpen(null);
    if (!open()) {
      if (event.key === 'ArrowRight') go(index() + 1);
      if (event.key === 'ArrowLeft') go(index() - 1);
    }
  };
  window.addEventListener('keydown', onKey);
  onCleanup(() => window.removeEventListener('keydown', onKey));

  // Desplazamiento con signo corto respecto a la diapositiva activa
  const offset = (i: number) => {
    let d = i - index();
    if (d > n / 2) d -= n;
    if (d < -n / 2) d += n;
    return d;
  };

  const styleFor = (d: number): JSX.CSSProperties => {
    const transition =
      'transform 700ms cubic-bezier(0.22, 1, 0.36, 1), opacity 500ms ease';
    if (d === 0) {
      return {
        transform: 'translate(-50%, -50%) translateZ(90px)',
        opacity: 1,
        'z-index': 30,
        transition,
      };
    }
    if (Math.abs(d) === 1) {
      return {
        transform: `translate(-50%, -50%) translateX(${d * 46}%) translateZ(-140px) rotateY(${-d * 42}deg) scale(0.8)`,
        opacity: 0.55,
        'z-index': 20,
        transition,
      };
    }
    return {
      transform: `translate(-50%, -50%) translateX(${d * 68}%) translateZ(-320px) rotateY(${-d * 32}deg) scale(0.65)`,
      opacity: 0,
      'z-index': 10,
      transition,
    };
  };

  return (
    <section id="capturas" class="overflow-hidden border-y border-white/5 bg-night-900/60 py-20">
      <div class="mx-auto max-w-6xl px-6">
        <SectionTitle
          eyebrow="Capturas"
          title="Así se ve NexusStream"
          subtitle="Un recorrido por la interfaz. Haz clic en la diapositiva central para ampliarla."
        />
      </div>

      {/* Escenario 3D */}
      <div
        class="relative mx-auto h-[300px] max-w-6xl sm:h-[380px] md:h-[440px] [perspective:1400px]"
        onMouseEnter={() => setPaused(true)}
        onMouseLeave={() => setPaused(false)}
      >
        <For each={SCREENS}>
          {(screen, i) => {
            const d = () => offset(i());
            const active = () => d() === 0;
            return (
              <div
                class="carousel-anim absolute left-1/2 top-1/2 w-[80%] max-w-[620px] cursor-pointer will-change-transform sm:w-[70%]"
                style={styleFor(d())}
                onClick={() => (active() ? setOpen(screen.src) : go(i()))}
              >
                {/* Halo del reflejo para la diapositiva activa */}
                <Show when={active()}>
                  <div
                    class="pointer-events-none absolute -inset-6 -z-10 rounded-3xl bg-brand-500/25 blur-3xl"
                    aria-hidden="true"
                  />
                </Show>
                <div
                  class={`overflow-hidden rounded-2xl border shadow-2xl transition duration-700 ${
                    active()
                      ? 'border-brand-400/50 shadow-brand-600/30'
                      : 'border-white/10 shadow-black/60'
                  }`}
                >
                  <Show
                    when={active()}
                    fallback={
                      <img
                        src={screen.src}
                        alt={screen.title}
                        loading="lazy"
                        class="aspect-video w-full object-cover object-top saturate-[0.55]"
                      />
                    }
                  >
                    {/* Activa: zoom sutil tipo Ken Burns + etiqueta */}
                    <div class="relative">
                      <img
                        src={screen.src}
                        alt={screen.title}
                        class="aspect-video w-full object-cover object-top"
                        style={{ animation: 'kenburns 6s ease-in-out infinite alternate' }}
                      />
                      <div class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/80 via-black/30 to-transparent p-4 sm:p-5">
                        <h3 class="text-base font-bold text-white sm:text-lg">{screen.title}</h3>
                        <p class="mt-0.5 line-clamp-1 text-xs text-slate-300 sm:text-sm">
                          {screen.text}
                        </p>
                      </div>
                    </div>
                    {/* Reflejo bajo la diapositiva activa */}
                    <div
                      class="pointer-events-none absolute inset-x-0 top-full h-[40%] overflow-hidden rounded-b-2xl"
                      aria-hidden="true"
                    >
                      <img
                        src={screen.src}
                        alt=""
                        class="w-full -scale-y-100 object-cover object-top opacity-25"
                        style={{
                          'mask-image':
                            'linear-gradient(to bottom, rgba(0,0,0,0.5), transparent 65%)',
                          '-webkit-mask-image':
                            'linear-gradient(to bottom, rgba(0,0,0,0.5), transparent 65%)',
                        }}
                      />
                    </div>
                  </Show>
                </div>
              </div>
            );
          }}
        </For>
      </div>

      {/* Controles: flechas, puntos con progreso y contador */}
      <div class="mx-auto mt-16 flex max-w-3xl items-center justify-center gap-4 px-6">
        <button
          type="button"
          onClick={() => go(index() - 1)}
          class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border border-white/10 bg-white/5 text-lg text-white transition hover:border-brand-400/60 hover:bg-white/10"
          aria-label="Captura anterior"
        >
          ‹
        </button>
        <div class="flex flex-1 items-center justify-center gap-2">
          <For each={SCREENS}>
            {(_, i) => {
              const active = () => index() === i();
              return (
                <button
                  type="button"
                  onClick={() => go(i())}
                  aria-label={`Ir a la captura ${i() + 1}`}
                  class={`relative h-1.5 overflow-hidden rounded-full transition-all duration-500 ${
                    active() ? 'w-10 bg-white/15' : 'w-4 bg-white/15 hover:bg-white/30'
                  }`}
                >
                  <Show when={active() && !reduceMotion}>
                    <span
                      ref={barRef}
                      class="absolute inset-0 origin-left rounded-full bg-brand-400"
                      style={{
                        animation: `progress-fill ${AUTOPLAY_MS}ms linear forwards`,
                        'animation-play-state': paused() ? 'paused' : 'running',
                      }}
                    />
                  </Show>
                </button>
              );
            }}
          </For>
        </div>
        <span
          class="w-14 shrink-0 text-center font-mono text-sm whitespace-nowrap text-slate-400"
          aria-hidden="true"
        >
          {String(index() + 1).padStart(2, '0')}
          <span class="text-slate-600"> / {String(n).padStart(2, '0')}</span>
        </span>
        <button
          type="button"
          onClick={() => go(index() + 1)}
          class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border border-white/10 bg-white/5 text-lg text-white transition hover:border-brand-400/60 hover:bg-white/10"
          aria-label="Captura siguiente"
        >
          ›
        </button>
      </div>

      {/* Visor a pantalla completa */}
      <Show when={open()}>
        <div
          class="fixed inset-0 z-[70] flex items-center justify-center bg-black/90 p-4 backdrop-blur-sm"
          role="dialog"
          aria-modal="true"
          onClick={() => setOpen(null)}
        >
          <button
            type="button"
            onClick={() => setOpen(null)}
            class="absolute right-5 top-4 flex h-10 w-10 items-center justify-center rounded-full bg-white/10 text-xl text-white transition hover:bg-white/20"
            aria-label="Cerrar captura"
          >
            ×
          </button>
          <img
            src={open()!}
            alt="Captura ampliada de NexusStream"
            class="max-h-[90vh] max-w-full rounded-xl border border-white/10 shadow-2xl"
            onClick={(event) => event.stopPropagation()}
          />
        </div>
      </Show>
    </section>
  );
};

const Checksum: Component<{ info?: DownloadInfo }> = (props) => (
  <Show when={props.info?.sha256}>
    <p class="mt-2 break-all font-mono text-xs text-slate-500">
      SHA-256: {props.info!.sha256}
    </p>
  </Show>
);

const DownloadSection: Component = () => (
  <section
    id="descargar"
    class="border-y border-white/5 bg-gradient-to-b from-night-800/70 to-night-900/70 py-20"
  >
    <div class="mx-auto max-w-6xl px-6">
      <SectionTitle
        eyebrow="Descargar"
        title="Instala NexusStream gratis"
        subtitle="Descarga directa, sin registros. Verifica el checksum si quieres confirmar la integridad del archivo."
      />
      <div class="grid gap-8 md:grid-cols-2 lg:grid-cols-3">
        <For each={DOWNLOAD_KINDS}>
          {(kind) => {
            const info = () => manifest()?.[kind];
            return (
              <div class="flex flex-col items-center rounded-3xl border border-white/5 bg-night-950/60 p-8 text-center">
                <div class="flex h-14 w-14 items-center justify-center rounded-2xl bg-brand-500/15 text-brand-400">
                  {platformIcon(kind)}
                </div>
                <h3 class="mt-4 text-lg font-bold text-white">
                  {kind === 'windows'
                    ? 'Windows (instalador)'
                    : kind === 'linux'
                      ? 'Linux x64 (tar.gz)'
                      : 'Android (APK)'}
                </h3>
                <p class="mt-1 text-sm text-slate-400">
                  {info()?.file ??
                    (kind === 'windows'
                      ? 'NexusStream-Setup-1.0.8.exe'
                      : kind === 'linux'
                        ? 'NexusStream-1.0.8-linux-x64.tar.gz'
                        : 'NexusStream-1.0.8.apk')}
                </p>
                <div class="mt-6">
                  <DownloadButton info={info()} kind={kind} size="lg" />
                </div>
                <Checksum info={info()} />
              </div>
            );
          }}
        </For>
      </div>
      <p class="mx-auto mt-10 max-w-2xl text-center text-xs leading-relaxed text-slate-500">
        En Android TV, activa la instalación de orígenes desconocidos para
        instalar el APK. En Windows, si SmartScreen muestra una advertencia,
        elige «Más información → Ejecutar de todas formas»: el instalador no
        está firmado con un certificado comercial. En Linux, extrae el tar.gz y
        ejecuta <code class="text-slate-300">./nexusstream</code> o el
        instalador de usuario incluido.
      </p>
    </div>
  </section>
);

const Footer: Component = () => (
  <footer class="py-10">
    <div class="mx-auto flex max-w-6xl flex-col items-center gap-4 px-6 text-center text-sm text-slate-500">
      <img src="/icon.png" alt="" class="h-8 w-8 rounded-lg" />
      <p>
        NexusStream {manifest()?.version ?? '1.0.0'} · No aloja ni distribuye
        contenido: reproduce listas y catálogos de terceros configurados por el
        usuario.
      </p>
      <p>© 2026 NexusStream</p>
    </div>
  </footer>
);

const App: Component = () => {
  const sections: JSX.Element[] = [
    <Hero />,
    <Features />,
    <Screenshots />,
    <Platforms />,
    <DownloadSection />,
  ];
  return (
    <div class="min-h-screen">
      <Navbar />
      <main>{sections}</main>
      <Footer />
    </div>
  );
};

export default App;
