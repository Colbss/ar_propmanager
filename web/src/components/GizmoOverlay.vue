<script setup lang="ts">
import { reactive, watch } from 'vue'
import { usePMStore } from '../stores/propmanager.store'

const pmStore = usePMStore()

// ─── Local editable state ─────────────────────────────────────────────────────

type Vec3Fields = { x: string; y: string; z: string }

const localPos = reactive<Vec3Fields>({ x: '0.0', y: '0.0', z: '0.0' })
const localRot = reactive<Vec3Fields>({ x: '0', y: '0', z: '0' })
const editingPos = reactive({ x: false, y: false, z: false })
const editingRot = reactive({ x: false, y: false, z: false })

watch(
  () => pmStore.displayPosition,
  (p) => {
    if (!editingPos.x) localPos.x = p.x.toFixed(1)
    if (!editingPos.y) localPos.y = p.y.toFixed(1)
    if (!editingPos.z) localPos.z = p.z.toFixed(1)
  },
  { deep: true }
)

watch(
  () => pmStore.displayRotation,
  (r) => {
    if (!editingRot.x) localRot.x = Math.round(r.x).toString()
    if (!editingRot.y) localRot.y = Math.round(r.y).toString()
    if (!editingRot.z) localRot.z = Math.round(r.z).toString()
  },
  { deep: true }
)

// ─── Commit helpers ───────────────────────────────────────────────────────────

function commit() {
  const px = parseFloat(localPos.x)
  const py = parseFloat(localPos.y)
  const pz = parseFloat(localPos.z)
  const rx = parseFloat(localRot.x)
  const ry = parseFloat(localRot.y)
  const rz = parseFloat(localRot.z)
  if ([px, py, pz, rx, ry, rz].some(isNaN)) return
  pmStore.applyManualTransform({ x: px, y: py, z: pz }, { x: rx, y: ry, z: rz })
}

function onFocus(group: typeof editingPos, axis: keyof Vec3Fields) {
  group[axis] = true
}

function onBlur(group: typeof editingPos, axis: keyof Vec3Fields) {
  group[axis] = false
  commit()
}

function onEnter(el: EventTarget | null) {
  ;(el as HTMLInputElement | null)?.blur()
}

function onEscape(
  el: EventTarget | null,
  group: typeof editingPos,
  axis: keyof Vec3Fields,
  local: Vec3Fields,
  storeVal: number,
  fmt: (n: number) => string
) {
  local[axis] = fmt(storeVal)
  group[axis] = false
  ;(el as HTMLInputElement | null)?.blur()
}

// ─── Copy / Paste ─────────────────────────────────────────────────────────────

function copyVec(v: Vec3Fields) {
  navigator.clipboard.writeText(`${v.x}, ${v.y}, ${v.z}`)
}

async function pasteVec(target: Vec3Fields, fmt: (n: number) => string) {
  const text = await navigator.clipboard.readText()
  const parts = text.split(',').map((s) => parseFloat(s.trim()))
  if (parts.length !== 3 || parts.some(isNaN)) return
  target.x = fmt(parts[0])
  target.y = fmt(parts[1])
  target.z = fmt(parts[2])
  commit()
}
</script>

<template>
  <Transition name="fade">
    <div v-if="pmStore.showOverlay" class="pointer-events-none absolute inset-0 z-10">

      <!-- ── Top left: Transform ────────────────────────────────────────── -->
      <div class="pointer-events-auto absolute left-4 top-4 w-52 rounded-lg border border-white/10 bg-black/75 p-3 text-white backdrop-blur-sm">

        <!-- Position -->
        <div class="mb-1 flex items-center justify-between">
          <span class="text-[11px] font-semibold uppercase tracking-wider text-slate-400">Position</span>
          <div class="flex gap-1">
            <button class="rounded p-0.5 text-slate-500 transition hover:text-slate-200" tabindex="-1" @click="copyVec(localPos)"><i class="pi pi-copy text-[11px]" /></button>
            <button class="rounded p-0.5 text-slate-500 transition hover:text-slate-200" tabindex="-1" @click="pasteVec(localPos, (n) => n.toFixed(1))"><i class="pi pi-clipboard text-[11px]" /></button>
          </div>
        </div>
        <div class="mb-3 flex flex-col gap-1">
          <div v-for="axis in (['x', 'y', 'z'] as const)" :key="'p' + axis" class="flex items-center gap-1.5">
            <span :class="{ 'text-red-400': axis === 'x', 'text-green-400': axis === 'y', 'text-blue-400': axis === 'z' }" class="w-3 text-center text-[11px] font-bold uppercase">{{ axis }}</span>
            <input
              v-model="localPos[axis]"
              type="text"
              class="min-w-0 flex-1 rounded border border-white/10 bg-white/5 px-1.5 py-0.5 font-mono text-xs text-slate-100 outline-none transition focus:border-white/30 focus:bg-white/10"
              @focus="onFocus(editingPos, axis)"
              @blur="onBlur(editingPos, axis)"
              @keydown.enter="onEnter($event.target)"
              @keydown.escape="onEscape($event.target, editingPos, axis, localPos, pmStore.displayPosition[axis], (n) => n.toFixed(1))"
            />
          </div>
        </div>

        <!-- Rotation -->
        <div class="mb-1 flex items-center justify-between">
          <span class="text-[11px] font-semibold uppercase tracking-wider text-slate-400">Rotation</span>
          <div class="flex gap-1">
            <button class="rounded p-0.5 text-slate-500 transition hover:text-slate-200" tabindex="-1" @click="copyVec(localRot)"><i class="pi pi-copy text-[11px]" /></button>
            <button class="rounded p-0.5 text-slate-500 transition hover:text-slate-200" tabindex="-1" @click="pasteVec(localRot, (n) => Math.round(n).toString())"><i class="pi pi-clipboard text-[11px]" /></button>
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <div v-for="axis in (['x', 'y', 'z'] as const)" :key="'r' + axis" class="flex items-center gap-1.5">
            <span :class="{ 'text-red-400': axis === 'x', 'text-green-400': axis === 'y', 'text-blue-400': axis === 'z' }" class="w-3 text-center text-[11px] font-bold uppercase">{{ axis }}</span>
            <input
              v-model="localRot[axis]"
              type="text"
              class="min-w-0 flex-1 rounded border border-white/10 bg-white/5 px-1.5 py-0.5 font-mono text-xs text-slate-100 outline-none transition focus:border-white/30 focus:bg-white/10"
              @focus="onFocus(editingRot, axis)"
              @blur="onBlur(editingRot, axis)"
              @keydown.enter="onEnter($event.target)"
              @keydown.escape="onEscape($event.target, editingRot, axis, localRot, pmStore.displayRotation[axis], (n) => Math.round(n).toString())"
            />
          </div>
        </div>
      </div>

      <!-- ── Top right: Controls ──────────────────────────────────────────── -->
      <div class="pointer-events-auto absolute right-4 top-4 flex w-44 flex-col gap-1.5 rounded-lg border border-white/10 bg-black/75 p-3 backdrop-blur-sm">
        <div class="flex gap-2 text-xs">
          <fieldset class="flex-1 rounded border border-white/20 px-2 py-1">
            <legend class="px-1 text-slate-400">Mode</legend>
            <span class="capitalize text-slate-100">{{ pmStore.editorMode }}</span>
          </fieldset>
          <fieldset class="flex-1 rounded border border-white/20 px-2 py-1">
            <legend class="px-1 text-slate-400">Space</legend>
            <span class="capitalize text-slate-100">{{ pmStore.spaceMode }}</span>
          </fieldset>
        </div>

        <div class="h-px bg-white/10" />

        <button class="rounded bg-white/10 px-3 py-1.5 text-xs text-white transition-colors hover:bg-white/20" @click="pmStore.toggleSpaceMode()">Toggle Axis Space</button>

        <template v-if="!pmStore.attachingProp">
          <button class="rounded bg-white/10 px-3 py-1.5 text-xs text-white transition-colors hover:bg-white/20" @click="pmStore.snapToGround()">Snap To Ground</button>
          <button class="rounded bg-white/10 px-3 py-1.5 text-xs text-white transition-colors hover:bg-white/20" @click="pmStore.resetRotation()">Reset Rotation</button>
        </template>

        <div class="h-px bg-white/10" />

        <button class="rounded bg-blue-600/80 px-3 py-1.5 text-xs font-medium text-white transition-colors hover:bg-blue-500/80" @click="pmStore.finish()">Done</button>
        <button class="rounded bg-red-600/80 px-3 py-1.5 text-xs font-medium text-white transition-colors hover:bg-red-500/80" @click="pmStore.cancel()">Cancel</button>
      </div>

      <!-- ── Bottom center: Keybinds ─────────────────────────────────────── -->
      <div class="pointer-events-none absolute bottom-4 left-1/2 flex -translate-x-1/2 gap-3">
        <div
          v-for="bind in [pmStore.keys.mode, pmStore.keys.focus, pmStore.keys.finish, pmStore.keys.cancel]"
          :key="bind.key"
          class="flex items-center gap-1.5 rounded-lg border border-white/10 bg-black/75 px-3 py-2 backdrop-blur-sm"
        >
          <kbd class="rounded bg-white/15 px-1.5 py-0.5 font-mono text-xs text-slate-100">{{ bind.key }}</kbd>
          <span class="text-xs text-slate-400">{{ bind.description }}</span>
        </div>
      </div>

    </div>
  </Transition>
</template>

<style scoped>
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.15s ease;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
