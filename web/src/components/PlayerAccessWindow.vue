<script setup lang="ts">
import { ref, reactive } from 'vue'
import { usePlayerAccessStore, type PlayerAccessEntry } from '../stores/playeraccess.store'
import { useApi } from '../composables/useApi'

const store = usePlayerAccessStore()

// ─── Form state ───────────────────────────────────────────────────────────────

const showForm = ref(false)
const editingId = ref<string | null>(null)

const emptyForm = () => ({
  name: '',
  identifier: '',
  group: '',
  hasArea: false,
  area: { x: '', y: '', z: '', radius: '' },
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
  form.area.x = entry.area ? String(entry.area.center.x) : ''
  form.area.y = entry.area ? String(entry.area.center.y) : ''
  form.area.z = entry.area ? String(entry.area.center.z) : ''
  form.area.radius = entry.area ? String(entry.area.radius) : ''
  editingId.value = entry.id
  showForm.value = true
}

const cancelForm = () => {
  showForm.value = false
  editingId.value = null
}

const buildArea = () => {
  if (!form.hasArea) return null
  return {
    center: { x: parseFloat(form.area.x) || 0, y: parseFloat(form.area.y) || 0, z: parseFloat(form.area.z) || 0 },
    radius: parseFloat(form.area.radius) || 0,
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
    form.area.x = result.data.value.x.toFixed(1)
    form.area.y = result.data.value.y.toFixed(1)
    form.area.z = result.data.value.z.toFixed(1)
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
</script>

<template>
  <div class="flex flex-col" @mousedown="pendingDelete = null">
    <!-- Toolbar -->
    <div class="flex items-center justify-between border-b border-white/10 px-4 py-2">
      <span class="text-[11px] text-slate-500">{{ store.entries.length }} player{{ store.entries.length !== 1 ? 's' : '' }} with access</span>
      <button
        class="flex items-center gap-1.5 rounded bg-white/10 px-2.5 py-1 text-xs text-slate-300 transition hover:bg-white/20"
        @click.stop="openAdd"
      >
        <i class="pi pi-plus text-[10px]" />
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
            <label class="text-[11px] text-slate-400">Player Name</label>
            <input
              v-model="form.name"
              type="text"
              placeholder="e.g. John"
              class="rounded border border-white/10 bg-white/5 px-2 py-1 text-xs text-slate-100 outline-none transition placeholder:text-slate-600 focus:border-white/25 focus:bg-white/10"
            />
          </div>

          <!-- Group -->
          <div class="flex flex-col gap-1">
            <label class="text-[11px] text-slate-400">Group</label>
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
            <label class="text-[11px] text-slate-400">Identifier</label>
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
            <div class="mb-2 flex items-center justify-between">
              <span class="text-[11px] text-slate-400">Area Center</span>
              <button
                class="flex items-center gap-1 rounded bg-white/10 px-2 py-0.5 text-[11px] text-slate-300 transition hover:bg-white/20 disabled:opacity-40"
                :disabled="fetchingPos"
                @click="useMyPosition"
              >
                <i class="pi pi-map-marker text-[10px]" />
                {{ fetchingPos ? 'Fetching…' : 'Use My Position' }}
              </button>
            </div>
            <div class="grid grid-cols-4 gap-1.5">
              <div v-for="(label, field) in { x: 'X', y: 'Y', z: 'Z' }" :key="field" class="flex flex-col gap-0.5">
                <span :class="{ 'text-red-400': field === 'x', 'text-green-400': field === 'y', 'text-blue-400': field === 'z' }" class="text-[10px] font-bold">{{ label }}</span>
                <input
                  v-model="form.area[field as 'x' | 'y' | 'z']"
                  type="text"
                  class="rounded border border-white/10 bg-black/40 px-1.5 py-0.5 font-mono text-xs text-slate-100 outline-none focus:border-white/25"
                />
              </div>
              <div class="flex flex-col gap-0.5">
                <span class="text-[10px] text-slate-400">Radius (m)</span>
                <input
                  v-model="form.area.radius"
                  type="text"
                  placeholder="50"
                  class="rounded border border-white/10 bg-black/40 px-1.5 py-0.5 font-mono text-xs text-slate-100 outline-none focus:border-white/25"
                />
              </div>
            </div>
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
    <div class="max-h-[400px] overflow-y-auto">
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
          <span class="truncate font-mono text-[11px] text-slate-500" :title="entry.identifier">{{ entry.identifier }}</span>
        </div>

        <!-- Group badge -->
        <span class="shrink-0 rounded bg-white/10 px-2 py-0.5 text-[11px] text-slate-300">
          {{ entry.group }}
        </span>

        <!-- Area badge -->
        <span
          class="shrink-0 rounded px-2 py-0.5 text-[11px]"
          :class="entry.area ? 'bg-blue-500/15 text-blue-400' : 'bg-white/5 text-slate-500'"
          :title="entry.area ? `Center: ${entry.area.center.x.toFixed(1)}, ${entry.area.center.y.toFixed(1)}, ${entry.area.center.z.toFixed(1)}` : ''"
        >
          {{ entry.area ? `◎ ${entry.area.radius}m` : 'No Area' }}
        </span>

        <!-- Actions -->
        <div class="flex shrink-0 gap-1">
          <button
            class="rounded px-2 py-1 text-slate-400 transition hover:bg-white/10 hover:text-slate-100"
            title="Edit"
            @click.stop="openEdit(entry)"
          >
            <i class="pi pi-pencil text-[11px]" />
          </button>
          <button
            class="rounded px-2 py-1 transition hover:bg-white/10"
            :class="pendingDelete === entry.id ? 'text-red-400' : 'text-slate-400 hover:text-slate-100'"
            :title="pendingDelete === entry.id ? 'Click again to confirm' : 'Revoke access'"
            @click.stop="requestDelete(entry.id)"
          >
            <i class="pi text-[11px]" :class="pendingDelete === entry.id ? 'pi-exclamation-triangle' : 'pi-trash'" />
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
  max-height: 400px;
}
.form-slide-enter-from,
.form-slide-leave-to {
  opacity: 0;
  max-height: 0;
}
</style>
