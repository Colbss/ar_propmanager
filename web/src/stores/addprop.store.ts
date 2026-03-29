import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useAddPropStore = defineStore('addProp', () => {
  const isVisible = ref(false)

  return { isVisible }
})
