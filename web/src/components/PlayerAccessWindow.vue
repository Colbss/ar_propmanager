<script setup lang="ts">
import { ref, reactive } from 'vue'
import { usePlayerAccessStore, type PlayerAccessEntry, type AreaRestriction } from '../stores/playeraccess.store'
import { useApi } from '../composables/useApi'
import MapZonePicker from './MapZonePicker.vue'

const store = usePlayerAccessStore()

// ─── Form state ───────────────────────────────────────────────────────────────

const showForm = ref(false)
const editingId = ref<string | null>(null)

const emptyForm = () => ({
  name: '',
  identifier: '',
  group: '',
  hasArea: false,
  areaType: 'radius' as 'radius' | 'zone',
  radius: { x: '', y: '', z: '', r: '' },
  zonePoints: [] as Array<{ x: number; y: number }>,
})

const form = reactive(emptyForm())

const openAdd = () => {
  Object.assign(form, emptyForm())
  editingId.value = null
  showForm.value = true
}

const openEdit = (entry: PlayerAccessEntry) => {
  form.name = entry.name
  form.identifier = entry.identifier
  form.group = entry.group
  form.hasArea = entry.area !== null

  if (entry.area?.type === 'zone') {
    form.areaType = 'zone'
    form.zonePoints = [...entry.area.points]
    form.radius = { x: '', y: '', z: '', r: '' }
  } else if (entry.area?.type === 'radius') {
    form.areaType = 'radius'
    form.radius.x = String(entry.area.center.x)
    form.radius.y = String(entry.area.center.y)
    form.radius.z = String(entry.area.center.z)
    form.radius.r = String(entry.area.radius)
    form.zonePoints = []
  } else {
    form.areaType = 'radius'
    form.radius = { x: '', y: '', z: '', r: '' }
    form.zonePoints = []
  }

  editingId.value = entry.id
  showForm.value = true
}

const cancelForm = () => {
  showForm.value = false
  editingId.value = null
}

const buildArea = (): AreaRestriction | null => {
  if (!form.hasArea) return null
  if (form.areaType === 'zone') {
    return { type: 'zone', points: [...form.zonePoints] }
  }
  return {
    type: 'radius',
    center: {
      x: parseFloat(form.radius.x) || 0,
      y: parseFloat(form.radius.y) || 0,
      z: parseFloat(form.radius.z) || 0,
    },
    radius: parseFloat(form.radius.r) || 0,
  }
}

const submitForm = () => {
  if (!form.name.trim() || !form.identifier.trim() || !form.group) return

  const payload = {
    name: form.name.trim(),
    identifier: form.identifier.trim(),
    group: form.group,
    area: buildArea(),
  }

  if (editingId.value) {
    store.updateEntry({ id: editingId.value, ...payload })
    const idx = store.entries.findIndex((e) => e.id === editingId.value)
    if (idx !== -1) store.entries[idx] = { id: editingId.value, ...payload }
  } else {
    store.addEntry(payload)
    store.entries.push({ id: `temp_${Date.now()}`, ...payload })
  }

  cancelForm()
}

// ─── Use current position ─────────────────────────────────────────────────────

const fetchingPos = ref(false)

const useMyPosition = async () => {
  fetchingPos.value = true
  const result = await useApi<{ x: number; y: number; z: number }>(
    'GetPlayerPosition',
    { method: 'POST', body: JSON.stringify({}) },
    undefined,
    { x: 100.0, y: 200.0, z: 30.0 }
  )
  if (result.data.value) {
    form.radius.x = result.data.value.x.toFixed(1)
    form.radius.y = result.data.value.y.toFixed(1)
    form.radius.z = result.data.value.z.toFixed(1)
  }
  fetchingPos.value = false
}

// ─── Confirm delete ───────────────────────────────────────────────────────────

const pendingDelete = ref<string | null>(null)

const requestDelete = (id: string) => {
  if (pendingDelete.value === id) {
    store.deleteEntry(id)
    pendingDelete.value = null
  } else {
    pendingDelete.value = id
  }
}

// ─── Area badge helpers ───────────────────────────────────────────────────────

function areaLabel(area: AreaRestriction | null) {
  if (!area) return 'No Area'
  if (area.type === 'zone') return `⬡ ${area.points.length} pts`
  return `◎ ${area.radius}m`
}

function areaTitle(area: AreaRestriction | null) {
  if (!area) return ''
  if (area.type === 'zone') return `Zone: ${area.points.length} vertices`
  return `Center: ${area.center.x.toFixed(1)}, ${area.center.y.toFixed(1)}, ${area.center.z.toFixed(1)} — Radius: ${area.radius}m`
}
</script>

<template>
  <div class="flex flex-col" @mousedown="pendingDelete = null">
    <!-- Toolbar -->
    <div class="flex items-center justify-between border-b border-white/10 px-4 py-2">
      <span class="text-xs text-slate-500">{{ store.entries.length }} player{{ store.entries.length !== 1 ? 's' : '' }} with access</span>
      <button
        class="flex items-center gap-1.5 rounded bg-white/10 px-2.5 py-1 text-xs text-slate-300 transition hover:bg-white/20"
        @click.stop="openAdd"
      >
        <i class="pi pi-plus text-[0.7rem]" />
        Grant Access
      </button>
    </div>

    <!-- Add / Edit form -->
    <Transition name="form-slide">
      <div v-if="showForm" class="border-b border-white/10 bg-white/5 p-4">
        <div class="mb-3 text-xs font-semibold text-slate-300">{{ editingId ? 'Edit Access Entry' : 'Grant Player Access' }}</div>

        <div class="mb-3 grid grid-cols-2 gap-2">
          <!-- Name -->
          <div class="flex flex-col gap-1">
            <label class="text-xs text-slate-400">Player Name</label>
            <input
              v-model="form.name"
              type="text"
              placeholder="e.g. John"
              class="rounded border border-white/10 bg-white/5 px-2 py-1 text-xs text-slate-100 outline-none transition placeholder:text-slate-600 focus:border-white/25 focus:bg-white/10"
            />
          </div>

          <!-- Group -->
          <div class="flex flex-col gap-1">
            <label class="text-xs text-slate-400">Group</label>
            <input
              v-model="form.group"
              list="access-groups"
              type="text"
              placeholder="Select or type group…"
              class="rounded border border-white/10 bg-white/5 px-2 py-1 text-xs text-slate-100 outline-none transition placeholder:text-slate-600 focus:border-white/25 focus:bg-white/10"
            />
            <datalist id="access-groups">
              <option v-for="g in store.availableGroups" :key="g" :value="g" />
            </datalist>
          </div>

          <!-- Identifier (full width) -->
          <div class="col-span-2 flex flex-col gap-1">
            <label class="text-xs text-slate-400">Identifier</label>
            <input
              v-model="form.identifier"
              type="text"
              placeholder="e.g. license:abc123…"
              class="rounded border border-white/10 bg-white/5 px-2 py-1 font-mono text-xs text-slate-100 outline-none transition placeholder:text-slate-600 focus:border-white/25 focus:bg-white/10"
            />
          </div>
        </div>

        <!-- Area restriction toggle -->
        <label class="mb-2 flex cursor-pointer items-center gap-2 text-xs">
          <input v-model="form.hasArea" type="checkbox" class="accent-blue-500" />
          <span class="text-slate-300">Restrict to area</span>
        </label>

        <!-- Area inputs -->
        <Transition name="form-slide">
          <div v-if="form.hasArea" class="mt-2 rounded border border-white/10 bg-white/5 p-3">
            <!-- Area type selector -->
            <div class="mb-3 flex gap-1.5">
              <button
                class="flex items-center gap-1.5 rounded px-2.5 py-1 text-xs transition"
                :class="form.areaType === 'radius'
                  ? 'bg-blue-600/50 text-blue-200'
                  : 'bg-white/5 text-slate-400 hover:bg-white/10 hover:text-slate-200'"
                @click="form.areaType = 'radius'"
              >
                <i class="pi pi-circle text-[0.7rem]" />
                Radius
              </button>
              <button
                class="flex items-center gap-1.5 rounded px-2.5 py-1 text-xs transition"
                :class="form.areaType === 'zone'
                  ? 'bg-blue-600/50 text-blue-200'
                  : 'bg-white/5 text-slate-400 hover:bg-white/10 hover:text-slate-200'"
                @click="form.areaType = 'zone'"
              >
                <i class="pi pi-map text-[0.7rem]" />
                Zone
              </button>
            </div>

            <!-- Radius inputs -->
            <template v-if="form.areaType === 'radius'">
              <div class="mb-2 flex items-center justify-between">
                <span class="text-xs text-slate-400">Area Center</span>
                <button
                  class="flex items-center gap-1 rounded bg-white/10 px-2 py-0.5 text-xs text-slate-300 transition hover:bg-white/20 disabled:opacity-40"
                  :disabled="fetchingPos"
                  @click="useMyPosition"
                >
                  <i class="pi pi-map-marker text-[0.7rem]" />
                  {{ fetchingPos ? 'Fetching…' : 'Use My Position' }}
                </button>
              </div>
              <div class="grid grid-cols-4 gap-1.5">
                <div v-for="(label, field) in { x: 'X', y: 'Y', z: 'Z' }" :key="field" class="flex flex-col gap-0.5">
                  <span :class="{ 'text-red-400': field === 'x', 'text-green-400': field === 'y', 'text-blue-400': field === 'z' }" class="text-[0.7rem] font-bold">{{ label }}</span>
                  <input
                    v-model="form.radius[field as 'x' | 'y' | 'z']"
                    type="text"
                    class="rounded border border-white/10 bg-black/40 px-1.5 py-0.5 font-mono text-xs text-slate-100 outline-none focus:border-white/25"
                  />
                </div>
                <div class="flex flex-col gap-0.5">
                  <span class="text-[0.7rem] text-slate-400">Radius (m)</span>
                  <input
                    v-model="form.radius.r"
                    type="text"
                    placeholder="50"
                    class="rounded border border-white/10 bg-black/40 px-1.5 py-0.5 font-mono text-xs text-slate-100 outline-none focus:border-white/25"
                  />
                </div>
              </div>
            </template>

            <!-- Zone inputs -->
            <template v-else>
              <MapZonePicker v-model="form.zonePoints" />
            </template>
          </div>
        </Transition>

        <!-- Form actions -->
        <div class="mt-3 flex justify-end gap-2">
          <button
            class="rounded bg-white/10 px-3 py-1.5 text-xs text-slate-300 transition hover:bg-white/20"
            @click="cancelForm"
          >
            Cancel
          </button>
          <button
            class="rounded bg-blue-600/80 px-3 py-1.5 text-xs font-medium text-white transition hover:bg-blue-500/80 disabled:opacity-40"
            :disabled="!form.name.trim() || !form.identifier.trim() || !form.group"
            @click="submitForm"
          >
            {{ editingId ? 'Save Changes' : 'Grant Access' }}
          </button>
        </div>
      </div>
    </Transition>

    <!-- Access list -->
    <div class="max-h-[40vh] overflow-y-auto">
      <div v-if="store.entries.length === 0" class="py-8 text-center text-xs text-slate-500">
        No players have been granted access.
      </div>

      <div
        v-for="entry in store.entries"
        :key="entry.id"
        class="flex items-center gap-2 border-b border-white/5 px-4 py-2.5 text-xs transition hover:bg-white/5"
      >
        <!-- Name + identifier -->
        <div class="flex min-w-0 flex-1 flex-col gap-0.5">
          <span class="truncate font-medium text-slate-100">{{ entry.name }}</span>
          <span class="truncate font-mono text-xs text-slate-500" :title="entry.identifier">{{ entry.identifier }}</span>
        </div>

        <!-- Group badge -->
        <span class="shrink-0 rounded bg-white/10 px-2 py-0.5 text-xs text-slate-300">
          {{ entry.group }}
        </span>

        <!-- Area badge -->
        <span
          class="shrink-0 rounded px-2 py-0.5 text-xs"
          :class="entry.area ? 'bg-blue-500/15 text-blue-400' : 'bg-white/5 text-slate-500'"
          :title="areaTitle(entry.area)"
        >
          {{ areaLabel(entry.area) }}
        </span>

        <!-- Actions -->
        <div class="flex shrink-0 gap-1">
          <button
            class="rounded px-2 py-1 text-slate-400 transition hover:bg-white/10 hover:text-slate-100"
            title="Edit"
            @click.stop="openEdit(entry)"
          >
            <i class="pi pi-pencil text-xs" />
          </button>
          <button
            class="rounded px-2 py-1 transition hover:bg-white/10"
            :class="pendingDelete === entry.id ? 'text-red-400' : 'text-slate-400 hover:text-slate-100'"
            :title="pendingDelete === entry.id ? 'Click again to confirm' : 'Revoke access'"
            @click.stop="requestDelete(entry.id)"
          >
            <i class="pi text-xs" :class="pendingDelete === entry.id ? 'pi-exclamation-triangle' : 'pi-trash'" />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.form-slide-enter-active,
.form-slide-leave-active {
  transition: opacity 0.15s ease, max-height 0.2s ease;
  overflow: hidden;
  max-height: 500px;
}
.form-slide-enter-from,
.form-slide-leave-to {
  opacity: 0;
  max-height: 0;
}
</style>
