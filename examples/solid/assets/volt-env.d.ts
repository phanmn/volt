declare module '*.svg' {
  const url: string
  export default url
}

interface ImportMetaEnv {
  MODE: string
  DEV: boolean
  PROD: boolean
  [key: string]: string | boolean | undefined
}

interface ImportMeta {
  env: ImportMetaEnv
  glob<T = unknown>(pattern: string, options?: { eager?: boolean }): Record<string, T>
  hot?: {
    data: Record<string, unknown>
    accept(callback?: (module?: unknown) => void): void
    accept(deps: string, callback?: (module?: unknown) => void): void
    accept(deps: string[], callback?: (modules: unknown[]) => void): void
    dispose(callback: (data: Record<string, unknown>) => void): void
  }
}
