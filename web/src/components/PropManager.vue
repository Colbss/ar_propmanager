<script setup lang="ts">
import { ref } from 'vue'
import PropManagerWindow from './PropManagerWindow.vue'
import AddPropWindow from './AddPropWindow.vue'
import { useNuiEvent } from '../composables/useNuiEvent'
import { usePropManagerStore, type PropEntry } from '../stores/propmanager.store'
import { usePlayerAccessStore, type PlayerAccessEntry } from '../stores/playeraccess.store'
import { useAddPropStore } from '../stores/addprop.store'

const propStore = usePropManagerStore()
const accessStore = usePlayerAccessStore()
const addPropStore = useAddPropStore()

const windowVisible = ref(false)
const activeTab = ref<'props' | 'permissions' | 'map'>('props')
const level = ref(0)

interface OpenPropManagerPayload {
  level: number
  props: PropEntry[]
  groupStates: Record<string, boolean>
  playerAccess?: PlayerAccessEntry[]
  groups?: string[]
}

function applyPayload(data: OpenPropManagerPayload) {
  level.value = data.level ?? 0
  propStore.props = (data.props ?? []).map((p) => ({ ...p, outlined: p.outlined ?? false }))
  propStore.groupStates = data.groupStates ?? {}
  propStore.applyGroupDefaults(propStore.groupStates)
  if (data.playerAccess) accessStore.entries = data.playerAccess
  if (data.groups) accessStore.availableGroups = data.groups
}

useNuiEvent<OpenPropManagerPayload>('openPropManager', (data) => {
  applyPayload(data)
  activeTab.value = data.level >= 1 ? 'props' : 'permissions'
  windowVisible.value = true
})

useNuiEvent<{ props: PropEntry[]; groupStates: Record<string, boolean> }>('updatePropList', (data) => {
  propStore.props = (data.props ?? []).map((p) => ({ ...p, outlined: p.outlined ?? false }))
  propStore.groupStates = data.groupStates ?? {}
  propStore.applyGroupDefaults(propStore.groupStates)
})

useNuiEvent('closePropManager', () => {
  windowVisible.value = false
})
</script>

<template>
  <PropManagerWindow
    v-if="windowVisible"
    v-model:activeTab="activeTab"
    :level="level"
    :class="addPropStore.isVisible ? 'opacity-40 blur-sm pointer-events-none' : 'transition-[opacity,filter] duration-150'"
    @close="windowVisible = false"
  />
  <AddPropWindow v-if="addPropStore.isVisible" />
</template>
