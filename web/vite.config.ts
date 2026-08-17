import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig(({ command }) => ({
  plugins: [react()],
  // На GitHub Pages сайт лежит в подпапке /AWS/, локально — в корне.
  // Без этого в собранной странице пути к js/css будут абсолютными от корня
  // домена и на Pages отдадут 404.
  base: command === 'build' ? '/AWS/' : '/',
}))
