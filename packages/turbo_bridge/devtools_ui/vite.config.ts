import { defineConfig } from 'vite';
import tailwindcss from '@tailwindcss/vite';
import { viteSingleFile } from 'vite-plugin-singlefile';
import path from 'node:path';

// Bundles the DevTools UI as a single self-contained index.html (with
// inlined JS + CSS) into ../lib/src/devtools/web/. That file is then
// declared in pubspec.yaml under flutter.assets and loaded at runtime
// via rootBundle by the Dart server.
export default defineConfig({
  plugins: [tailwindcss(), viteSingleFile()],
  build: {
    outDir: path.resolve(__dirname, '../lib/src/devtools/web'),
    emptyOutDir: false,
    minify: 'esbuild',
    cssMinify: true,
    target: 'es2020',
    rollupOptions: {
      output: {
        inlineDynamicImports: true,
      },
    },
  },
});
