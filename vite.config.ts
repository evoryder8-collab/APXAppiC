import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// GitHub Pages serves the app from /APXAppiC/, local dev from the root.
export default defineConfig(({ command }) => ({
  base: command === 'build' ? '/APXAppiC/' : '/',
  plugins: [react(), tailwindcss()],
  server: {
    port: 5174,
    strictPort: true,
  },
}))
