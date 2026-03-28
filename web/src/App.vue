<script setup lang="ts">
import { defineAsyncComponent, onMounted } from 'vue'
import { useGizmoStore } from './stores/gizmo.store'
import { useDevelopment } from './stores/development.store'

const DevelopmentToolbar = defineAsyncComponent(() => import('./devComponents/DevelopmentToolbar.vue'))
const Gizmo = defineAsyncComponent(() => import('./components/Gizmo.vue'))
const PropManager = defineAsyncComponent(() => import('./components/PropManager.vue'))

const dev = useDevelopment()
const gizmoStore = useGizmoStore()

onMounted(() => {
  if (dev.isDevEnv) {
    dev.applyDevelopmentStyles()
  }
})

</script>

<template>

 <Gizmo v-show="gizmoStore.isVisible" />
 <PropManager />
 <DevelopmentToolbar v-if="dev.isDevEnv" />
</template>

<style scoped>

</style>
