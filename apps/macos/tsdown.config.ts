import { defineConfig } from 'tsdown'

/** Build the native process carrier while keeping its deployable package dependencies external. */
export default defineConfig({
  entry: ['Host/sidecar.ts'],
  outDir: 'lib',
  format: ['esm'],
  platform: 'node',
  target: 'es2024',
  fixedExtension: false,
  dts: false,
  clean: true,
  deps: {
    skipNodeModulesBundle: true,
  },
})
