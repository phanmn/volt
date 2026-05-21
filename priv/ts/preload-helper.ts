const __voltPreload = (load: () => Promise<unknown>, deps: string[]) =>
  Promise.all(
    deps.map(dep => {
      const link = document.createElement('link')
      link.rel = dep.endsWith('.css') ? 'stylesheet' : 'modulepreload'
      link.href = dep
      document.head.appendChild(link)

      if (link.rel !== 'stylesheet') {
        return Promise.resolve()
      }

      return new Promise((resolve, reject) => {
        link.onload = resolve
        link.onerror = reject
      })
    })
  ).then(load)
