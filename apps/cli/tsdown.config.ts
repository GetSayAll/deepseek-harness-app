import { defineConfig } from 'tsdown'

/**
 * The dsh CLI ships its command entry and the profile boot API consumed by
 * native application carriers. Declarations come from `tsc -b` (dts: false),
 * matching every package.
 */
export default defineConfig({
  entry: ['lib/types/bin.js', 'lib/types/profile-boot.js'],
  outDir: 'lib',
  format: ['esm'],
  platform: 'node',
  target: 'es2024',
  fixedExtension: false,
  dts: false,
  clean: false,
})
