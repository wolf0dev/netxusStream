// Copia los artefactos ya compilados de la app (dist/ de la raíz del
// proyecto) a `landing/public/downloads/` y genera `manifest.json` con
// tamaños y SHA-256. Los archivos viven en el código fuente, así que
// Vercel (o cualquier hosting) los sirve sin pasos extra.
//
//   npm run sync-downloads     (solo cuando cambie el APK o el instalador)
import { createHash } from 'node:crypto';
import { copyFile, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const landing = path.resolve(here, '..');
const repoRoot = path.resolve(landing, '..');
const dist = path.join(repoRoot, 'dist');
const out = path.join(landing, 'public', 'downloads');

const ARTIFACTS = [
  {
    key: 'windows',
    source: path.join(dist, 'NexusStream-Setup-1.0.0.exe'),
    file: 'NexusStream-Setup-1.0.0.exe',
    label: 'Instalador de Windows',
  },
  {
    key: 'android',
    source: path.join(dist, 'NexusStream-1.0.0.apk'),
    file: 'NexusStream-1.0.0.apk',
    label: 'APK de Android',
  },
];

const sha256 = async (file) => {
  const buffer = await readFile(file);
  return createHash('sha256').update(buffer).digest('hex').toUpperCase();
};

try {
  await mkdir(out, { recursive: true });
  const manifest = { version: '1.0.0', generatedAt: new Date().toISOString() };
  for (const artifact of ARTIFACTS) {
    await copyFile(artifact.source, path.join(out, artifact.file));
    const { size } = await stat(artifact.source);
    manifest[artifact.key] = {
      file: artifact.file,
      label: artifact.label,
      bytes: size,
      sha256: await sha256(artifact.source),
    };
    console.log(`copiado: ${artifact.file} (${(size / 1e6).toFixed(1)} MB)`);
  }
  await writeFile(
    path.join(out, 'manifest.json'),
    JSON.stringify(manifest, null, 2),
  );
  console.log('manifest.json generado en public/downloads/');
} catch (error) {
  console.error(
    'No se pudieron copiar los artefactos. Compila antes la app:\n' +
      '  cd tv && flutter build windows --release && flutter build apk --release\n',
  );
  console.error(error.message);
  process.exit(1);
}
