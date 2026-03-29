<script setup lang="ts">
import { ref } from 'vue'
import PropManagerWindow from './PropManagerWindow.vue'
import { useNuiEvent } from '../composables/useNuiEvent'
import { usePropManagerStore, type PropEntry } from '../stores/propmanager.store'
import { usePlayerAccessStore, type PlayerAccessEntry } from '../stores/playeraccess.store'

const propStore = usePropManagerStore()
const accessStore = usePlayerAccessStore()

const windowVisible = ref(false)
const activeTab = ref<'props' | 'permissions' | 'map'>('props')

interface PropPayload {
  props: PropEntry[]
  groupStates: Record<string, boolean>
}

function applyPropPayload(data: PropPayload) {
  propStore.props = data.props.map((p) => ({ ...p, outlined: p.outlined ?? false }))
  propStore.groupStates = data.groupStates ?? {}
}

// ─── Prop list events ─────────────────────────────────────────────────────────

useNuiEvent<PropPayload>('openPropManager', (data) => {
  applyPropPayload(data)
  activeTab.value = 'props'
  windowVisible.value = true
})

useNuiEvent<PropPayload>('updatePropList', (data) => {
  applyPropPayload(data)
})

useNuiEvent('closePropManager', () => {
  windowVisible.value = false
})

// ─── Player access events ─────────────────────────────────────────────────────

useNuiEvent<{ permissions: PlayerAccessEntry[]; groups: string[] }>('openPermissions', (data) => {
  accessStore.entries = data.permissions
  accessStore.availableGroups = data.groups
  activeTab.value = 'permissions'
  windowVisible.value = true
})

useNuiEvent<{ permissions: PlayerAccessEntry[] }>('updatePermissions', (data) => {
  accessStore.entries = data.permissions
})

useNuiEvent('closePermissions', () => {
  windowVisible.value = false
})
</script>

<template>
  <PropManagerWindow
    v-if="windowVisible"
    v-model:activeTab="activeTab"
    @close="windowVisible = false"
  />
</template>
