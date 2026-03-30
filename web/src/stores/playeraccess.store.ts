import { defineStore } from 'pinia'
import { ref } from 'vue'
import { useApi } from '../composables/useApi'

export interface RadiusArea {
  type: 'radius'
  center: { x: number; y: number; z: number }
  radius: number
}

export interface ZoneArea {
  type: 'zone'
  points: Array<{ x: number; y: number }>
}

export type AreaRestriction = RadiusArea | ZoneArea

export interface PlayerAccessEntry {
  id: number
  identifier: string
  name: string
  groups: string[]
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
    console.log('Updating entry:', entry)
    useApi('UpdatePlayerAccess', { method: 'POST', body: JSON.stringify(entry) }, undefined, {})
  }

  const deleteEntry = (id: number) => {
    useApi('DeletePlayerAccess', { method: 'POST', body: JSON.stringify({ id }) }, undefined, {})
    entries.value = entries.value.filter((e) => e.id !== id)
  }

  return { isVisible, entries, availableGroups, addEntry, updateEntry, deleteEntry }
})
