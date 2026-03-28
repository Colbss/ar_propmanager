import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

export const usePMStore = defineStore('pm', () => {
    const isVisible = ref<boolean>(false)


    return {
        isVisible
    }

})
