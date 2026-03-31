<script setup lang="ts">
import { ref, computed, reactive, onMounted } from 'vue'
import { useAddPropStore } from '../stores/addprop.store'
import { usePropManagerStore } from '../stores/propmanager.store'
import { useApi } from '../composables/useApi'

const emit = defineEmits<{ done: [] }>()

const addPropStore = useAddPropStore()
const propStore    = usePropManagerStore()

// ─── Prop list ────────────────────────────────────────────────────────────────

const propList    = ref<string[]>([])
const listLoading = ref(true)

onMounted(async () => {
  const result = await useApi<string[]>(
    'GetPropList',
    { method: 'POST', body: JSON.stringify({}) },
    undefined,
    [
      'prop_bench_01a', 'prop_bench_01b', 'prop_tree_pine_01a',
      'prop_streetlight_01', 'prop_bin_01a', 'prop_bollard_01',
      'prop_barrier_01a', 'prop_cone_01', 'prop_box_wood01a',
    ]
  )
  propList.value = result.data.value ?? []
  listLoading.value = false
})

// ─── Fuzzy search ─────────────────────────────────────────────────────────────

const searchQuery = ref('')
const showResults = ref(false)

function scoreMatch(query: string, target: string): number {
  const q = query.toLowerCase()
  const t = target.toLowerCase()

  if (t === q) return 100
  if (t.startsWith(q)) return 80
  if (t.includes(q)) return 60

  const qSegs = q.split(/[_\s-]+/).filter(Boolean)
  const tSegs = t.split(/[_\s-]+/)
  let segScore = 0
  for (const qs of qSegs) {
    if (tSegs.some((ts) => ts.startsWith(qs))) segScore += 20
    else if (t.includes(qs)) segScore += 10
  }
  if (segScore > 0) return segScore

  let qi = 0
  for (const c of t) {
    if (qi < q.length && c === q[qi]) qi++
  }
  return qi === q.length ? Math.max(1, Math.floor((qi / t.length) * 8)) : 0
}

const filteredProps = computed(() => {
  const q = searchQuery.value.trim()
  if (!q) return propList.value.slice(0, 20)
  return propList.value
    .map((p) => ({ p, s: scoreMatch(q, p) }))
    .filter((x) => x.s > 0)
    .sort((a, b) => b.s - a.s)
    .slice(0, 60)
    .map((x) => x.p)
})

const selectProp = (name: string) => {
  searchQuery.value = name
  showResults.value = false
}

const onBlur = () => {
  setTimeout(() => { showResults.value = false }, 150)
}

// ─── Form state ───────────────────────────────────────────────────────────────

const existingGroups = computed(() =>
  addPropStore.allowedGroups.length > 0
    ? addPropStore.allowedGroups
    : [...propStore.groups.keys()]
)

const form = reactive({
  group:          '',
  renderDistance: 200,
  hasExpiry:      false,
  expiresAt:      '',
})

// ─── Group dropdown ───────────────────────────────────────────────────────────

const showGroupResults = ref(false)

const filteredGroups = computed(() => {
  const q = form.group.trim().toLowerCase()
  if (!q) return existingGroups.value
  return existingGroups.value.filter((g) => g.toLowerCase().includes(q))
})

const selectGroup = (name: string) => {
  form.group = name
  showGroupResults.value = false
}

const onGroupBlur = () => {
  setTimeout(() => { showGroupResults.value = false }, 150)
}

const canPlace = computed(() =>
  searchQuery.value.trim().length > 0 && form.group.trim().length > 0
)

// ─── Submit ───────────────────────────────────────────────────────────────────

const placing = ref(false)
const error   = ref('')

const place = async () => {
  if (!canPlace.value) return
  placing.value = true
  error.value   = ''

  await useApi(
    'PlaceProp',
    {
      method: 'POST',
      body: JSON.stringify({
        model:          searchQuery.value.trim(),
        group:          form.group.trim(),
        renderDistance: form.renderDistance,
        expiresAt:      form.hasExpiry && form.expiresAt
          ? Math.floor(new Date(form.expiresAt).getTime() / 1000)
          : null,
      }),
    },
    undefined,
    {}
  )

  placing.value = false
  emit('done')
}
</script>

<template>
  <div class="flex flex-col gap-4 p-4">

    <!-- Model search -->
    <div class="flex flex-col gap-1.5">
      <label class="text-xs font-medium text-slate-400">Prop Model</label>
      <div class="relative">
        <div class="pointer-events-none absolute inset-y-0 left-2.5 flex items-center">
          <i class="pi pi-search text-xs text-slate-500" />
        </div>
        <input
          v-model="searchQuery"
          type="text"
          placeholder="Search or type model name…"
          class="w-full rounded border border-white/10 bg-white/5 py-1.5 pl-7 pr-3 text-xs text-slate-100 outline-none transition placeholder:text-slate-600 focus:border-white/25 focus:bg-white/10"
          @focus="showResults = true"
          @blur="onBlur"
        />

        <!-- Results dropdown -->
        <div
          v-if="showResults && filteredProps.length > 0"
          class="absolute top-full z-10 mt-1 max-h-[20vh] w-full overflow-y-auto rounded border border-white/10 bg-black/95 shadow-xl"
        >
          <div v-if="listLoading" class="px-3 py-2 text-xs text-slate-500">Loading prop list…</div>
          <button
            v-for="name in filteredProps"
            :key="name"
            class="flex w-full items-center px-3 py-1.5 text-left text-xs text-slate-300 transition hover:bg-white/10 hover:text-slate-100"
            @mousedown.prevent="selectProp(name)"
          >
            <span class="font-mono">{{ name }}</span>
          </button>
        </div>
      </div>
      <p v-if="searchQuery && !propList.includes(searchQuery)" class="text-[0.7rem] text-amber-400/80">
        <i class="pi pi-exclamation-triangle mr-1 text-[0.6rem]" />
        Not in list — will be validated in-game
      </p>
    </div>

    <!-- Group + Render distance (2-col) -->
    <div class="grid grid-cols-2 gap-3">
      <div class="flex flex-col gap-1.5">
        <label class="text-xs font-medium text-slate-400">Group</label>
        <!-- Restricted: fixed group buttons -->
        <div v-if="addPropStore.allowedGroups.length > 0" class="flex flex-wrap gap-1">
          <button
            v-for="g in existingGroups"
            :key="g"
            type="button"
            class="rounded px-2 py-1 text-xs transition"
            :class="form.group === g
              ? 'bg-blue-600/60 text-blue-200 ring-1 ring-blue-500/40'
              : 'bg-white/5 text-slate-400 hover:bg-white/10 hover:text-slate-200'"
            @click.stop="form.group = g"
          >{{ g }}</button>
        </div>
        <!-- Unrestricted: styled dropdown -->
        <div v-else class="relative">
          <div class="pointer-events-none absolute inset-y-0 left-2.5 flex items-center">
            <i class="pi pi-tag text-xs text-slate-500" />
          </div>
          <input
            v-model="form.group"
            type="text"
            placeholder="Select or type group…"
            class="w-full rounded border border-white/10 bg-white/5 py-1.5 pl-7 pr-3 text-xs text-slate-100 outline-none transition placeholder:text-slate-600 focus:border-white/25 focus:bg-white/10"
            @focus="showGroupResults = true"
            @blur="onGroupBlur"
          />
          <div
            v-if="showGroupResults && filteredGroups.length > 0"
            class="absolute top-full z-10 mt-1 max-h-[16vh] w-full overflow-y-auto rounded border border-white/10 bg-black/95 shadow-xl"
          >
            <button
              v-for="g in filteredGroups"
              :key="g"
              class="flex w-full items-center px-3 py-1.5 text-left text-xs text-slate-300 transition hover:bg-white/10 hover:text-slate-100"
              @mousedown.prevent="selectGroup(g)"
            >{{ g }}</button>
          </div>
        </div>
      </div>

      <div class="flex flex-col gap-1.5">
        <label class="text-xs font-medium text-slate-400">Render Distance (m)</label>
        <input
          v-model.number="form.renderDistance"
          type="number"
          min="1"
          max="1000"
          step="1"
          @change="form.renderDistance = Math.min(1000, Math.max(1, form.renderDistance))"
          class="rounded border border-white/10 bg-white/5 px-2.5 py-1.5 text-xs text-slate-100 outline-none transition focus:border-white/25 focus:bg-white/10"
        />
      </div>
    </div>

    <!-- Expiry -->
    <div class="flex flex-col gap-1.5">
      <label class="flex cursor-pointer items-center gap-2 text-xs font-medium text-slate-400">
        <input v-model="form.hasExpiry" type="checkbox" class="accent-blue-500" />
        Set Expiry
      </label>
      <Transition name="form-slide">
        <input
          v-if="form.hasExpiry"
          v-model="form.expiresAt"
          type="datetime-local"
          class="rounded border border-white/10 bg-white/5 px-2.5 py-1.5 text-xs text-slate-100 outline-none transition focus:border-white/25 focus:bg-white/10 [color-scheme:dark]"
        />
      </Transition>
    </div>

    <!-- Error -->
    <p v-if="error" class="text-xs text-red-400">{{ error }}</p>

    <!-- Actions -->
    <div class="flex justify-end gap-2 border-t border-white/5 pt-2">
      <button
        class="rounded bg-white/10 px-3 py-1.5 text-xs text-slate-300 transition hover:bg-white/20"
        @click="emit('done')"
      >
        Cancel
      </button>
      <button
        class="flex items-center gap-1.5 rounded bg-blue-600/80 px-3 py-1.5 text-xs font-medium text-white transition hover:bg-blue-500/80 disabled:opacity-40"
        :disabled="!canPlace || placing"
        @click="place"
      >
        <i class="pi pi-map-marker text-[0.7rem]" />
        {{ placing ? 'Placing…' : 'Place Prop' }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.form-slide-enter-active,
.form-slide-leave-active {
  transition: opacity 0.15s ease, max-height 0.2s ease;
  overflow: hidden;
  max-height: 60px;
}
.form-slide-enter-from,
.form-slide-leave-to {
  opacity: 0;
  max-height: 0;
}
</style>
