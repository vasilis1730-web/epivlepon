import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { viteSingleFile } from 'vite-plugin-singlefile'
import path from 'node:path'

// Build που παράγει ΕΝΑ αυτόνομο αρχείο HTML (όλα τα JS/CSS ενσωματωμένα),
// για δημοσίευση ως ζωντανή προεπισκόπηση σε λειτουργία επίδειξης.
export default defineConfig({
  plugins: [react(), viteSingleFile()],
  resolve: { alias: { '@': path.resolve(__dirname, './src') } },
  build: {
    outDir: 'dist-single',
    assetsInlineLimit: 100000000,
    cssCodeSplit: false,
    reportCompressedSize: false,
  },
})
