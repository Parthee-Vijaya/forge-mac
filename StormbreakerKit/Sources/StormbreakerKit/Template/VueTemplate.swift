import Foundation

/// Vue 3 + Vite + TypeScript + Tailwind CSS v4 scaffold. Verified to
/// `npm install` + `vite build` cleanly. The model authors `src/App.vue`.
extension ProjectTemplate {
    public static let viteVueTailwind = ProjectTemplate(
        files: [
            File(path: "package.json", contents: vuePackageJSON),
            File(path: "vite.config.ts", contents: vueViteConfig),
            File(path: "index.html", contents: vueIndexHTML),
            File(path: "src/main.ts", contents: vueMainTS),
            File(path: "src/App.vue", contents: vueAppVue),
            File(path: "src/style.css", contents: vueStyleCSS),
            File(path: "src/vite-env.d.ts", contents: vueEnvDTS),
            File(path: "tsconfig.json", contents: vueTSConfig),
            File(path: ".gitignore", contents: frameworkGitignore),
        ],
        modelEntryFile: "src/App.vue"
    )
}

// vue-tsc reads this to type-check `.vue` SFCs (the self-correction loop's type
// gate). `include` covers src only — vite.config.ts needs node types we don't
// ship, and Vite validates its own config at runtime.
private let vueTSConfig = """
{
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "module": "ESNext",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "preserve",
    "strict": true,
    "noUnusedLocals": false,
    "noUnusedParameters": false
  },
  "include": ["src/**/*.ts", "src/**/*.tsx", "src/**/*.vue"]
}
"""

private let vuePackageJSON = """
{
  "name": "storm-app",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "vue": "^3.5.0"
  },
  "devDependencies": {
    "@vitejs/plugin-vue": "^5.2.0",
    "@tailwindcss/vite": "^4.0.0",
    "tailwindcss": "^4.0.0",
    "typescript": "^5.6.0",
    "vue-tsc": "^2.1.0",
    "vite": "^6.0.0"
  }
}
"""

private let vueViteConfig = """
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

// strictPort is false so Vite recovers to the next free port; --host (passed by
// Stormbreaker) binds LAN interfaces for the shared live link.
export default defineConfig({
  plugins: [vue(), tailwindcss()],
  server: { host: '127.0.0.1', strictPort: false },
})
"""

private let vueIndexHTML = """
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Stormbreaker App</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/src/main.ts"></script>
  </body>
</html>
"""

private let vueMainTS = """
import { createApp } from 'vue'
import './style.css'
import App from './App.vue'

createApp(App).mount('#app')
"""

private let vueAppVue = """
<script setup lang="ts">
import { ref } from 'vue'

const count = ref(0)
</script>

<template>
  <main class="min-h-screen flex items-center justify-center bg-white text-neutral-900">
    <button
      class="px-5 py-2.5 rounded-lg bg-black text-white font-medium hover:bg-neutral-800"
      @click="count++"
    >
      Clicked {{ count }} times
    </button>
  </main>
</template>
"""

private let vueStyleCSS = """
@import "tailwindcss";
"""

private let vueEnvDTS = """
/// <reference types="vite/client" />

declare module '*.vue' {
  import type { DefineComponent } from 'vue'
  const component: DefineComponent<{}, {}, any>
  export default component
}
"""

/// Shared .gitignore for the non-React (Svelte/Vue) scaffolds.
let frameworkGitignore = """
node_modules
dist
dist-ssr
*.local
.DS_Store
.forge
"""
