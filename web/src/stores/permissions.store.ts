import { defineStore } from 'pinia'
import { ref } from 'vue'
import { useApi } from '../composables/useApi'

export interface AreaRestriction {
  center: { x: number; y: number; z: number }
  radius: number
}

export interface UserPermission {
  id: string
  identifier: string
  name: string
  group: string
  area: AreaRestriction | null
}

export const usePermissionsStore = defineStore('permissions', () => {
  const isVisible = ref(false)
  const permissions = ref<UserPermission[]>([])
  const availableGroups = ref<string[]>([])

  const addPermission = (data: Omit<UserPermission, 'id'>) => {
    useApi('AddPermission', { method: 'POST', body: JSON.stringify(data) }, undefined, {})
  }

  const updatePermission = (permission: UserPermission) => {
    useApi('UpdatePermission', { method: 'POST', body: JSON.stringify(permission) }, undefined, {})
  }

  const deletePermission = (id: string) => {
    useApi('DeletePermission', { method: 'POST', body: JSON.stringify({ id }) }, undefined, {})
    permissions.value = permissions.value.filter((p) => p.id !== id)
  }

  return { isVisible, permissions, availableGroups, addPermission, updatePermission, deletePermission }
})
