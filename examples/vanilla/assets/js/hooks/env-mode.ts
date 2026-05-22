import type { ViewHook } from 'phoenix_live_view'

const EnvMode: Partial<ViewHook> = {
  mounted() {
    if (!this.el) return
    this.el.textContent = import.meta.env.MODE
  },
}

export default EnvMode
