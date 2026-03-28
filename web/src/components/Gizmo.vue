<script setup lang="ts">
import ThreeScene from './ThreeScene.vue'
import GizmoOverlay from './GizmoOverlay.vue'
import { useNuiEvent } from '../composables/useNuiEvent'
import { usePMStore } from '../stores/propmanager.store'

const pmStore = usePMStore()

useNuiEvent('show', () => {
  pmStore.isVisible = true
})

useNuiEvent('hide', () => {
  pmStore.isVisible = false
})
</script>

<template>
  <div class="relative h-screen w-screen">
    <ThreeScene />
    <GizmoOverlay />
  </div>
</template>
