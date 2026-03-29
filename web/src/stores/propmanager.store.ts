import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { useApi } from '../composables/useApi'

export interface PropEntry {
  id: string
  netId?: number
  handle: number
  model: string
  position: { x: number; y: number; z: number }
  group: string
  outlined: boolean
  renderDistance?: number
  expiresAt?: number | null
}

export const usePropManagerStore = defineStore('propManager', () => {
  const isVisible = ref(false)
  const props = ref<PropEntry[]>([])
  const groupStates = ref<Record<string, boolean>>({})

  // ─── Group collapse state ─────────────────────────────────────────────────
  // Persists across tab switches and window open/close.
  // Inactive groups are auto-collapsed the first time they are seen.

  const collapsedGroups = ref(new Set<string>())
  const seenGroups = ref(new Set<string>())

  const applyGroupDefaults = (newStates: Record<string, boolean>) => {
    for (const [name, enabled] of Object.entries(newStates)) {
      if (!seenGroups.value.has(name)) {
        if (!enabled) collapsedGroups.value = new Set([...collapsedGroups.value, name])
        seenGroups.value = new Set([...seenGroups.value, name])
      }
    }
  }

  const toggleCollapsed = (name: string) => {
    const next = new Set(collapsedGroups.value)
    if (next.has(name)) next.delete(name)
    else next.add(name)
    collapsedGroups.value = next
  }

  const groups = computed(() => {
    const map = new Map<string, PropEntry[]>()
    for (const prop of props.value) {
      if (!map.has(prop.group)) map.set(prop.group, [])
      map.get(prop.group)!.push(prop)
    }
    return map
  })

  const teleport = (id: string) => {
    const prop = props.value.find((p) => p.id === id)
    useApi('TeleportToProp', { method: 'POST', body: JSON.stringify({ id, netId: prop?.netId }) }, undefined, {})
  }

  const outline = (id: string) => {
    useApi('OutlineProp', { method: 'POST', body: JSON.stringify({ id }) }, undefined, {})
    const prop = props.value.find((p) => p.id === id)
    if (prop) prop.outlined = !prop.outlined
  }

  const deleteProp = (id: string) => {
    useApi('DeleteProp', { method: 'POST', body: JSON.stringify({ id }) }, undefined, {})
    props.value = props.value.filter((p) => p.id !== id)
  }

  const outlineAll = () => {
    const target = !props.value.every((p) => p.outlined)
    for (const prop of props.value) prop.outlined = target
    useApi('OutlineAllProps', { method: 'POST', body: JSON.stringify({ outlined: target }) }, undefined, {})
  }

  const toggleGroup = (group: string, enabled: boolean) => {
    useApi('ToggleGroup', { method: 'POST', body: JSON.stringify({ group, enabled }) }, undefined, {})
    // Optimistic update — will be corrected by the server's syncPropList broadcast
    groupStates.value = { ...groupStates.value, [group]: enabled }
  }

  return { isVisible, props, groupStates, groups, collapsedGroups, applyGroupDefaults, toggleCollapsed, teleport, outline, outlineAll, deleteProp, toggleGroup }
})
