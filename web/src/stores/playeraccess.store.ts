import { defineStore } from 'pinia'
import { ref } from 'vue'
import { useApi } from '../composables/useApi'

export interface AreaRestriction {
  center: { x: number; y: number; z: number }
  radius: number
}

export interface PlayerAccessEntry {
  id: string
  identifier: string
  name: string
  group: string
  area: AreaRestriction | null
}

export const usePlayerAccessStore = defineStore('playerAccess', () => {
  const isVisible = ref(false)
  const entries = ref<PlayerAccessEntry[]>([])
  const availableGroups = ref<string[]>([])

  const addEntry = (data: Omit<PlayerAccessEntry, 'id'>) => {
    useApi('AddPlayerAccess', { method: 'POST', body: JSON.stringify(data) }, undefined, {})
  }

  const updateEntry = (entry: PlayerAccessEntry) => {
    useApi('UpdatePlayerAccess', { method: 'POST', body: JSON.stringify(entry) }, undefined, {})
  }

  const deleteEntry = (id: string) => {
    useApi('DeletePlayerAccess', { method: 'POST', body: JSON.stringify({ id }) }, undefined, {})
    entries.value = entries.value.filter((e) => e.id !== id)
  }

  return { isVisible, entries, availableGroups, addEntry, updateEntry, deleteEntry }
})
