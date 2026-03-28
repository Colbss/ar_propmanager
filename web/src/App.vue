<script setup lang="ts">
import { defineAsyncComponent, onMounted } from 'vue'
import { usePMStore } from './stores/propmanager.store'
import { useDevelopment } from './stores/development.store'

const DevelopmentToolbar = defineAsyncComponent(() => import('./devComponents/DevelopmentToolbar.vue'))
const Gizmo = defineAsyncComponent(() => import('./components/Gizmo.vue'))

const dev = useDevelopment()
const pmStore = usePMStore()

onMounted(() => {
  if (dev.isDevEnv) {
    dev.applyDevelopmentStyles()
  }

})

</script>

<template>
 
 <Gizmo v-show="pmStore.isVisible" />
 <DevelopmentToolbar v-if="dev.isDevEnv" />
</template>

<style scoped>

</style>