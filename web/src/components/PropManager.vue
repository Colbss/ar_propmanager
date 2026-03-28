<script setup lang="ts">
import { ref } from 'vue'
import PropManagerWindow from './PropManagerWindow.vue'
import { useNuiEvent } from '../composables/useNuiEvent'
import { usePropManagerStore, type PropEntry } from '../stores/propmanager.store'
import { usePermissionsStore, type UserPermission } from '../stores/permissions.store'

const propStore = usePropManagerStore()
const permStore = usePermissionsStore()

const windowVisible = ref(false)
const activeTab = ref<'props' | 'permissions'>('props')

// ─── Prop list events ─────────────────────────────────────────────────────────

useNuiEvent<{ props: PropEntry[] }>('openPropManager', (data) => {
  propStore.props = data.props.map((p) => ({ ...p, outlined: p.outlined ?? false }))
  activeTab.value = 'props'
  windowVisible.value = true
})

useNuiEvent<{ props: PropEntry[] }>('updatePropList', (data) => {
  propStore.props = data.props.map((p) => ({ ...p, outlined: p.outlined ?? false }))
})

useNuiEvent('closePropManager', () => {
  windowVisible.value = false
})

// ─── Permissions events ───────────────────────────────────────────────────────

useNuiEvent<{ permissions: UserPermission[]; groups: string[] }>('openPermissions', (data) => {
  permStore.permissions = data.permissions
  permStore.availableGroups = data.groups
  activeTab.value = 'permissions'
  windowVisible.value = true
})

useNuiEvent<{ permissions: UserPermission[] }>('updatePermissions', (data) => {
  permStore.permissions = data.permissions
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
