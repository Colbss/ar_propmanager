<script setup lang="ts">
import ThreeScene from './ThreeScene.vue'
import GizmoOverlay from './GizmoOverlay.vue'
import { useNuiEvent } from '../composables/useNuiEvent'
import { useGizmoStore } from '../stores/gizmo.store'

const pmStore = useGizmoStore()

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
