<script setup lang="ts">
import { usePMStore } from '../stores/propmanager.store'
import { useDevelopment } from '../stores/development.store'
import SplitButton from 'primevue/splitbutton'

const dev = useDevelopment()
const pmStore = usePMStore()

const debugData = (data: any) => {
  window.postMessage(data, '*')
}

const items = [
  {
    label: 'Show Vehicle HUD',
    command: () =>
      debugData({
        action: 'addNetwork',
        data: {
          ssid: 'test_w_password',
          label: 'Test W Password',
          password: '1234'
        }
      })
  },
]
</script>
<template>
  <div class="fixed left-5 top-5 flex gap-5">
    <SplitButton
      label="Toggle HUD State"
      dropdownIcon="pi pi-chevron-down"
      @click.prevent="pmStore.isVisible = !pmStore.isVisible"
      :model="items"
      size="small"
    />
  </div>
</template>