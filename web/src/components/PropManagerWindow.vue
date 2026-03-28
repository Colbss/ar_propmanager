<script setup lang="ts">
import { ref } from 'vue'
import { useDraggable } from '@vueuse/core'
import PropListWindow from './PropListWindow.vue'
import PlayerAccessWindow from './PlayerAccessWindow.vue'

const props = defineProps<{
  activeTab: 'props' | 'permissions'
}>()

const emit = defineEmits<{
  'update:activeTab': [tab: 'props' | 'permissions']
  close: []
}>()

// ─── Draggable window ─────────────────────────────────────────────────────────

const titleBar = ref<HTMLElement | null>(null)
const windowEl = ref<HTMLElement | null>(null)

const { style } = useDraggable(windowEl, {
  handle: titleBar,
  initialValue: { x: Math.max(0, (window.innerWidth - 560) / 2), y: 120 },
})
</script>

<template>
  <Transition name="window-fade">
    <div
      ref="windowEl"
      :style="style"
      class="fixed z-20 flex w-[560px] flex-col overflow-hidden rounded-xl border border-white/10 bg-black/85 text-white shadow-2xl backdrop-blur-md"
    >
      <!-- Title bar -->
      <div
        ref="titleBar"
        class="flex cursor-grab select-none items-center justify-between border-b border-white/10 px-4 py-2.5 active:cursor-grabbing"
      >
        <div class="flex items-center gap-2 text-sm font-semibold text-slate-200">
          <i class="pi pi-objects-column text-slate-400" />
          Prop Manager
        </div>
        <button
          class="rounded p-1 text-slate-500 transition hover:text-slate-200"
          @click.stop="emit('close')"
        >
          <i class="pi pi-times text-xs" />
        </button>
      </div>

      <!-- Tab strip -->
      <div class="flex border-b border-white/10 bg-white/3">
        <button
          class="flex items-center gap-1.5 px-4 py-2 text-xs font-medium transition"
          :class="activeTab === 'props'
            ? 'border-b-2 border-blue-400 text-blue-400'
            : 'text-slate-400 hover:text-slate-200'"
          @click="emit('update:activeTab', 'props')"
        >
          <i class="pi pi-list text-[11px]" />
          Props
        </button>
        <button
          class="flex items-center gap-1.5 px-4 py-2 text-xs font-medium transition"
          :class="activeTab === 'permissions'
            ? 'border-b-2 border-blue-400 text-blue-400'
            : 'text-slate-400 hover:text-slate-200'"
          @click="emit('update:activeTab', 'permissions')"
        >
          <i class="pi pi-users text-[11px]" />
          Player Access
        </button>
      </div>

      <!-- Tab content -->
      <PropListWindow v-if="activeTab === 'props'" />
      <PlayerAccessWindow v-else />
    </div>
  </Transition>
</template>

<style scoped>
.window-fade-enter-active,
.window-fade-leave-active {
  transition: opacity 0.15s ease, transform 0.15s ease;
}
.window-fade-enter-from,
.window-fade-leave-to {
  opacity: 0;
  transform: scale(0.97);
}
</style>
