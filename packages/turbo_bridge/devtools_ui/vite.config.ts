import { defineConfig } from 'vite';
import tailwindcss from '@tailwindcss/vite';
import { viteSingleFile } from 'vite-plugin-singlefile';
import path from 'node:path';

// Bundles the DevTools UI as a single self-contained index.html (with
// inlined JS + CSS) into ./dist/. The host DevTools server (turbo_bridge_mcp)
// embeds that file as a Dart const via tool/embed_devtools.dart — the app no
// longer ships the UI as a Flutter asset.
export default defineConfig({
  plugins: [tailwindcss(), viteSingleFile()],
  build: {
    outDir: path.resolve(__dirname, 'dist'),
    emptyOutDir: true,
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
