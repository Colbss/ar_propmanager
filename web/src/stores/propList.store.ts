import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { useApi } from '../composables/useApi'

export interface PropEntry {
  id: string
  handle: number
  model: string
  position: { x: number; y: number; z: number }
  group: string
  outlined: boolean
}

export const usePropListStore = defineStore('propList', () => {
  const isVisible = ref(false)
  const props = ref<PropEntry[]>([])

  const groups = computed(() => {
    const map = new Map<string, PropEntry[]>()
    for (const prop of props.value) {
      if (!map.has(prop.group)) map.set(prop.group, [])
      map.get(prop.group)!.push(prop)
    }
    return map
  })

  const teleport = (id: string) => {
    useApi('TeleportToProp', { method: 'POST', body: JSON.stringify({ id }) }, undefined, {})
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

  return { isVisible, props, groups, teleport, outline, deleteProp }
})
