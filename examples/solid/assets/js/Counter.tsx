import { createMemo, createSignal } from 'solid-js'

export default function Counter() {
  const [count, setCount] = createSignal(0)
  const doubled = createMemo(() => count() * 2)

  return (
    <div>
      <button
        type="button"
        class="rounded-full bg-cyan-600 px-5 py-2.5 font-semibold text-white shadow-md shadow-cyan-600/25 transition hover:-translate-y-0.5 hover:bg-cyan-700"
        onClick={() => setCount((value) => value + 1)}
      >
        Count is {count()}
      </button>
      <p class="mt-3 text-sm text-slate-500">Doubled: {doubled()}</p>
    </div>
  )
}
