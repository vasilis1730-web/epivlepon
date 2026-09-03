import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'node:path'

/**
 * Στην παραγωγή η εφαρμογή δημοσιεύεται στο GitHub Pages, κάτω από τη
 * διαδρομή /epivlepon/. Στην ανάπτυξη σερβίρεται από τη ρίζα.
 * Το VITE_BASE επιτρέπει διαφορετική διαδρομή χωρίς αλλαγή κώδικα
 * (π.χ. VITE_BASE=/ για φιλοξενία σε δικό σας domain).
 */
export default defineConfig(({ mode }) => ({
  base: process.env.VITE_BASE ?? (mode === 'production' ? '/epivlepon/' : '/'),
  plugins: [react()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  server: { port: 5173, host: true },
}))
