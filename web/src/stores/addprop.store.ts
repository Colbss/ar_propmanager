import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useAddPropStore = defineStore('addProp', () => {
  const isVisible = ref(false)
  const allowedGroups = ref<string[]>([])  // non-empty = restricted to these groups only

  return { isVisible, allowedGroups }
})
