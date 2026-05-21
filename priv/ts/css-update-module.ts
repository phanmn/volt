import { removeStyle as __volt_removeStyle, updateStyle as __volt_updateStyle } from '/@volt/client.js'

const __volt_id = '__VOLT_CSS_ID__'
const __volt_css = '__VOLT_CSS__'

__volt_updateStyle(__volt_id, __volt_css)

if (import.meta.hot) {
  import.meta.hot.accept()
  import.meta.hot.dispose(() => __volt_removeStyle(__volt_id))
}
