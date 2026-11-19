import { createResource } from 'solid-js';

export interface DownloadInfo {
  file: string;
  label: string;
  bytes: number;
  sha256: string;
}

export interface Manifest {
  version: string;
  generatedAt: string;
  windows?: DownloadInfo;
  android?: DownloadInfo;
  linux?: DownloadInfo;
}

const FALLBACK: Manifest = {
  version: '1.0.0',
  generatedAt: '',
};

/**
 * Tamaños y checksums reales de los instaladores. El manifiesto lo genera
 * `scripts/copy-downloads.mjs` al construir; si no está disponible (por
 * ejemplo en `vite dev`), se usan valores por defecto sin tamaño.
 */
export const [manifest] = createResource(async () => {
  try {
    const response = await fetch('/downloads/manifest.json');
    if (!response.ok) return FALLBACK;
    return (await response.json()) as Manifest;
  } catch {
    return FALLBACK;
  }
});

export const formatBytes = (bytes?: number) => {
  if (!bytes || bytes <= 0) return '';
  const mb = bytes / (1024 * 1024);
  if (mb >= 1000) return `${(mb / 1024).toFixed(2)} GB`;
  return `${mb.toFixed(1)} MB`;
};

export const downloadUrl = (info?: DownloadInfo) =>
  info ? `/downloads/${info.file}` : undefined;
