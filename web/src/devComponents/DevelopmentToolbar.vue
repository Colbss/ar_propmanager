<script setup lang="ts">
import { useGizmoStore } from '../stores/gizmo.store'
import SplitButton from 'primevue/splitbutton'

const pmStore = useGizmoStore()

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

const mockGroups = ['Street Furniture', 'Nature', 'Vehicles']
const mockModels = [
  'prop_bench_01a', 'prop_tree_pine_01a', 'prop_streetlight_01',
  'prop_barrier_01a', 'prop_bin_01a', 'prop_bollard_01',
]
const mockGroupStates: Record<string, boolean> = {
  'Street Furniture': true,
  'Nature': false,
  'Vehicles': true,
}
const mockPlayerAccess = [
  { id: 'perm_1', identifier: 'license:a1b2c3d4e5f6a1b2c3d4', name: 'John Doe',   groups: ['Street Furniture', 'Vehicles'], area: null },
  { id: 'perm_2', identifier: 'license:f6e5d4c3b2a1f6e5d4c3', name: 'Jane Smith', groups: ['Nature'],                       area: { center: { x: 215.4, y: -810.2, z: 29.7 }, radius: 100 } },
]

function buildMockProps() {
  const now = Math.floor(Date.now() / 1000)
  const mockExpiries = [null, now + 3600, now + 86400, now - 60]
  return Array.from({ length: 12 }, (_, i) => ({
    id: i + 1,
    model: mockModels[i % mockModels.length],
    position: { x: +(100 + i * 30).toFixed(1), y: +(200 + i * 1.2).toFixed(1), z: +(28 + (i % 4) * 0.5).toFixed(1) },
    quaternion: { x: 0, y: 0, z: 0, w: 1 },
    group: mockGroups[i % mockGroups.length],
    outlined: false,
    renderDistance: 200,
    expiresAt: mockExpiries[i % mockExpiries.length],
  }))
}

const testPropManager = (level: number) => {
  const data: Record<string, any> = { level, props: buildMockProps(), groupStates: mockGroupStates }
  if (level >= 3) {
    data.playerAccess = mockPlayerAccess
    data.groups = mockGroups
  }
  debugData({ action: 'openPropManager', data })
}

const items = [
  { label: 'Test Gizmo',                command: testGizmo },
  {
    label: 'Close Gizmo',
    command: () => {
      debugData({ action: 'closeGizmo', data: {} })
      debugData({ action: 'hide', data: {} })
      pmStore.isVisible = false
      pmStore.showOverlay = false
    }
  },
  { label: 'Prop Manager — Level 1 (toggle groups)', command: () => testPropManager(1) },
  { label: 'Prop Manager — Level 2 (manage)',         command: () => testPropManager(2) },
  { label: 'Prop Manager — Level 3 (player access)',  command: () => testPropManager(3) },
  { label: 'Close Prop Manager', command: () => debugData({ action: 'closePropManager', data: {} }) },
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
