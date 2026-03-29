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

const testPropManager = () => {
  const mockGroups = ['Street Furniture', 'Nature', 'Vehicles']
  const mockModels = [
    'prop_bench_01a', 'prop_tree_pine_01a', 'prop_streetlight_01',
    'prop_barrier_01a', 'prop_bin_01a', 'prop_bollard_01',
  ]
  const now = Math.floor(Date.now() / 1000)
  const mockExpiries = [
    null,
    now + 3600,   // expires in 1 hour
    now + 86400,  // expires in 24 hours
    now - 60,     // already expired
  ]
  const props = Array.from({ length: 12 }, (_, i) => ({
    id: `prop_${i}`,
    handle: i + 1,
    model: mockModels[i % mockModels.length],
    position: { x: +(100 + i * 3.7).toFixed(1), y: +(200 + i * 1.2).toFixed(1), z: +(28 + (i % 4) * 0.5).toFixed(1) },
    group: mockGroups[i % mockGroups.length],
    outlined: false,
    renderDistance: 200,
    expiresAt: mockExpiries[i % mockExpiries.length],
  }))
  const groupStates: Record<string, boolean> = {
    'Street Furniture': true,
    'Nature': false,
    'Vehicles': true,
  }
  debugData({ action: 'openPropManager', data: { props, groupStates } })
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
  },
  {
    label: 'Test Prop Manager',
    command: testPropManager
  },
  {
    label: 'Close Prop Manager',
    command: () => debugData({ action: 'closePropManager', data: {} })
  },
  {
    label: 'Test Permissions',
    command: () => debugData({
      action: 'openPermissions',
      data: {
        groups: ['Street Furniture', 'Nature', 'Vehicles'],
        permissions: [
          {
            id: 'perm_1',
            identifier: 'license:a1b2c3d4e5f6a1b2c3d4',
            name: 'John Doe',
            group: 'Street Furniture',
            area: null,
          },
          {
            id: 'perm_2',
            identifier: 'license:f6e5d4c3b2a1f6e5d4c3',
            name: 'Jane Smith',
            group: 'Nature',
            area: { center: { x: 215.4, y: -810.2, z: 29.7 }, radius: 100 },
          },
        ],
      },
    })
  },
  {
    label: 'Close Permissions',
    command: () => debugData({ action: 'closePermissions', data: {} })
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
