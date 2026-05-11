function assert(value, message) {
  if (!value) {
    throw new Error(message || 'assertion failed')
  }
}

assert.ok = assert
assert.equal = (actual, expected, message) => {
  if (actual != expected) {
    throw new Error(message || 'assert equal failed')
  }
}
assert.strictEqual = (actual, expected, message) => {
  if (actual !== expected) {
    throw new Error(message || 'assert strictEqual failed')
  }
}

const path = {
  sep: '/',
  basename(value) {
    return String(value).split('/').pop() || ''
  },
  dirname(value) {
    const parts = String(value).split('/')
    parts.pop()
    return parts.join('/') || '.'
  },
  extname(value) {
    const base = path.basename(value)
    const index = base.lastIndexOf('.')
    return index > 0 ? base.slice(index) : ''
  },
  join(...parts) {
    return parts.join('/')
  },
  resolve(...parts) {
    return parts.join('/')
  }
}

globalThis.require = (name) => {
  if (name === 'assert') return assert
  if (name === 'path') return path
  throw new Error(`unsupported require ${name}`)
}

let compiler

async function loadCompiler() {
  if (compiler) return compiler

  const Babel = await import('@babel/standalone')
  const solidPreset = await import('babel-preset-solid')
  Babel.registerPreset('solid', solidPreset.default)
  compiler = Babel
  return compiler
}

async function compileSolid(source, options = {}) {
  const Babel = await loadCompiler()
  const filename = options.filename ?? 'component.tsx'
  const typescript = options.typescript ?? /\.[cm]?tsx?$/.test(filename)

  const presets = []

  if (typescript) {
    presets.push([
      'typescript',
      {
        isTSX: /\.tsx$/.test(filename),
        allExtensions: true,
        allowDeclareFields: true,
        ...(options.typescriptOptions ?? {})
      }
    ])
  }

  presets.push(['solid', options.solidOptions ?? {}])

  const result = Babel.transform(source, {
    filename,
    sourceMaps: options.sourcemap ?? true,
    presets
  })

  return {
    code: result.code ?? '',
    map: result.map ?? null
  }
}

globalThis.compileSolid = compileSolid
