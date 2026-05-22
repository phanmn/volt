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

declare namespace JSX {
  interface IntrinsicElements {
    [elementName: string]: unknown
  }
}

declare module 'react' {
  export type ReactNode = unknown
  export function useState<S>(initial: S): [S, (value: S | ((previous: S) => S)) => void]
  export function useMemo<T>(factory: () => T, deps: unknown[]): T
}

declare module 'react-dom/client' {
  export interface Root {
    render(node: unknown): void
  }

  export function createRoot(element: Element): Root
}

declare module 'react/jsx-runtime' {
  export const Fragment: unknown
  export function jsx(type: unknown, props: unknown, key?: unknown): unknown
  export function jsxs(type: unknown, props: unknown, key?: unknown): unknown
}
