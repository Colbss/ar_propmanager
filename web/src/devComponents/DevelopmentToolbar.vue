<script setup lang="ts">
import { usePMStore } from '../stores/propmanager.store'
import SplitButton from 'primevue/splitbutton'

const pmStore = usePMStore()

const debugData = (data: any) => {
  window.postMessage(data, '*')
}

const testGizmo = () => {
  pmStore.isVisible = true
  // Short delay so the canvas is visible before we send the camera/entity events
  setTimeout(() => {
    debugData({
      action: 'setCameraPosition',
      data: {
        position: { x: 0, y: -12, z: 3 },
        rotation: { x: -10, y: 0, z: 0 },
        fov: 60
      }
    })
    debugData({
      action: 'setGizmoEntity',
      data: {
        handle: 1,
        position: { x: 0, y: 0, z: 0 },
        quaternion: { x: 0, y: 0, z: 0, w: 1 },
        keybinds: {
          mode:   { key: 'R',    description: 'Change Mode' },
          focus:  { key: 'F',    description: 'Toggle Focus' },
          finish: { key: 'E',    description: 'Finish' },
          cancel: { key: 'Back', description: 'Cancel' },
        },
        attachingProp: false,
        simpleOverlay: false,
        restrictRotationAxes: false
      }
    })
  }, 50)
}

const items = [
  {
    label: 'Test Gizmo',
    command: testGizmo
  },
  {
    label: 'Close Gizmo',
    command: () => {
      debugData({ action: 'closeGizmo', data: {} })
      debugData({ action: 'hide', data: {} })
      pmStore.isVisible = false
      pmStore.showOverlay = false
    }
  }
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
