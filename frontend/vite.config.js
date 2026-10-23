import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// /api calls are forwarded to the Flask server, so no CORS issues in dev
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: { '/api': 'http://localhost:5000' },
  },
})
