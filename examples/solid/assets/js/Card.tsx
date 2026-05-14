import type { JSX } from 'solid-js'

export default function Card(props: { title: string; children: JSX.Element }) {
  return (
    <div class="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
      <h2 class="mb-3 text-xs font-bold uppercase tracking-widest text-slate-400">{props.title}</h2>
      {props.children}
    </div>
  )
}
