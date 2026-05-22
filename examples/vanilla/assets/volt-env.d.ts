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

declare module 'phoenix' {
  export class Socket {
    constructor(path: string, options?: unknown)
  }
}

declare module 'phoenix_html'

declare module 'phoenix_live_view' {
  export interface ViewHook<E extends HTMLElement = HTMLElement> {
    el: E
    timer?: ReturnType<typeof setInterval>
    mounted?(): void
    destroyed?(): void
  }

  export class LiveSocket {
    constructor(path: string, socket: typeof import('phoenix').Socket, options?: unknown)
    connect(): void
  }
}
