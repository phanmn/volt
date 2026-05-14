import { For } from 'solid-js'
import { render } from 'solid-js/web'
import config from './config.json'
import logo from '../images/volt.svg'
import Counter from './Counter'
import Card from './Card'

const pages = import.meta.glob('./pages/*.ts', { eager: true }) as Record<
  string,
  { title: string; description: string }
>

function App() {
  return (
    <main class="mx-auto mt-12 max-w-2xl space-y-8 px-6 pb-12">
      <header class="flex items-center gap-4">
        <img src={logo} alt="" class="h-10 w-10 text-cyan-500" />
        <div>
          <h1 class="text-4xl font-black tracking-tight text-slate-950">{config.name} + Solid</h1>
          <p class="text-sm text-slate-500">v{config.version}</p>
        </div>
      </header>

      <Card title="Counter">
        <Counter />
      </Card>

      <Card title="Pages (glob import)">
        <ul class="space-y-2">
          <For each={Object.entries(pages)}>
            {([_path, page]) => (
              <li class="flex items-baseline gap-2">
                <span class="font-semibold text-slate-800">{page.title}</span>
                <span class="text-sm text-slate-500">{page.description}</span>
              </li>
            )}
          </For>
        </ul>
      </Card>

      <footer class="text-center text-xs text-slate-400">Mode: {import.meta.env.MODE}</footer>
    </main>
  )
}

const dispose = render(() => <App />, document.getElementById('app')!)

if (import.meta.hot) {
  import.meta.hot.dispose(() => {
    dispose()
  })
  import.meta.hot.accept()
}
