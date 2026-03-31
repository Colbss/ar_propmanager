import { defineStore } from 'pinia'
import { ref } from 'vue'
import { useApi } from '../composables/useApi'

export interface RadiusArea {
  type: 'radius'
  center: { x: number; y: number }
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
  maxExpiry: number | null  // forced expiry duration in seconds, null = no limit
}

export const usePlayerAccessStore = defineStore('playerAccess', () => {
  const isVisible = ref(false)
  const entries = ref<PlayerAccessEntry[]>([])
  const availableGroups = ref<string[]>([])

  const addEntry = (data: Omit<PlayerAccessEntry, 'id'>) => {
    useApi<PlayerAccessEntry>(
      'AddPlayerAccess',
      { method: 'POST', body: JSON.stringify(data) },
      undefined,
      { id: Date.now(), ...data },
    ).then((result) => {
      const entry = result.data?.value
      if (entry && typeof entry === 'object' && 'id' in entry) {
        entries.value.push(entry as PlayerAccessEntry)
      }
    })
  }

  const updateEntry = (entry: PlayerAccessEntry) => {
    useApi<string>('UpdatePlayerAccess', { method: 'POST', body: JSON.stringify(entry) }, undefined, 'ok')
      .then(() => {
        const idx = entries.value.findIndex((e) => e.id === entry.id)
        if (idx !== -1) entries.value[idx] = entry
      })
  }

  const deleteEntry = (id: number) => {
    useApi<string>('DeletePlayerAccess', { method: 'POST', body: JSON.stringify({ id }) }, undefined, 'ok')
      .then(() => {
        entries.value = entries.value.filter((e) => e.id !== id)
      })
  }

  return { isVisible, entries, availableGroups, addEntry, updateEntry, deleteEntry }
})
