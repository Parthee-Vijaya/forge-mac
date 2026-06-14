import Foundation

/// A baked-in project scaffold copied into each new project before the first
/// model turn. Shrinking the model's job to "fill in src/App.tsx" dramatically
/// raises first-run success — the fragile boilerplate (Vite/Tailwind wiring,
/// package.json, entry HTML) is always correct.
public struct ProjectTemplate: Sendable {
    public struct File: Sendable {
        public let path: String
        public let contents: String
        public init(path: String, contents: String) {
            self.path = path
            self.contents = contents
        }
    }

    public let files: [File]
    /// The file the model is expected to author/overwrite first.
    public let modelEntryFile: String

    public init(files: [File], modelEntryFile: String) {
        self.files = files
        self.modelEntryFile = modelEntryFile
    }

    /// React + Vite + TypeScript + Tailwind CSS v4 (the only stack the skeleton
    /// targets). Tailwind v4's Vite plugin removes the fragile PostCSS/content
    /// globbing of v3.
    public static let viteReactTailwind = ProjectTemplate(
        files: [
            File(path: "package.json", contents: templatePackageJSON),
            File(path: "vite.config.ts", contents: templateViteConfig),
            File(path: "tsconfig.json", contents: templateTSConfig),
            File(path: "tsconfig.node.json", contents: templateTSConfigNode),
            File(path: "index.html", contents: templateIndexHTML),
            File(path: "src/main.tsx", contents: templateMainTSX),
            File(path: "src/index.css", contents: templateIndexCSS),
            File(path: "src/App.tsx", contents: templateAppTSX),
            File(path: ".gitignore", contents: templateGitignore),
        ],
        modelEntryFile: "src/App.tsx"
    )
}

// MARK: - File contents (column-0 multiline literals)

private let templatePackageJSON = """
{
  "name": "forge-app",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  },
  "devDependencies": {
    "@tailwindcss/vite": "^4.0.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "@vitejs/plugin-react": "^4.3.4",
    "tailwindcss": "^4.0.0",
    "typescript": "^5.6.0",
    "vite": "^6.0.0"
  }
}
"""

private let templateViteConfig = """
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// Pin host so the loaded URL matches the app's ATS exception. strictPort is
// false so Vite recovers to the next free port; Forge parses the actual port
// from stdout (never assume 5173).
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    host: '127.0.0.1',
    strictPort: false,
  },
})
"""

private let templateTSConfig = """
{
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": false,
    "noUnusedParameters": false,
    "noFallthroughCasesInSwitch": true
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
"""

private let templateTSConfigNode = """
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2023"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": true
  },
  "include": ["vite.config.ts"]
}
"""

private let templateIndexHTML = """
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Forge App</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
"""

private let templateMainTSX = """
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App.tsx'
import './index.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
"""

private let templateIndexCSS = """
@import "tailwindcss";

:root {
  color-scheme: light dark;
}

html,
body,
#root {
  height: 100%;
}

body {
  margin: 0;
  background: #ffffff;
  color: #000000;
  font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
}
"""

private let templateAppTSX = """
export default function App() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-white text-black">
      <div className="text-center">
        <h1 className="text-2xl font-semibold tracking-tight">Forge</h1>
        <p className="mt-2 text-sm text-neutral-500">
          Describe the app you want to build.
        </p>
      </div>
    </div>
  )
}
"""

private let templateGitignore = """
node_modules
dist
.forge
*.local
"""
