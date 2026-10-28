import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
export default defineConfig({ site: 'https://roll.cloakyard.com', output: 'static', devToolbar: { enabled: false }, integrations: [sitemap()] });
