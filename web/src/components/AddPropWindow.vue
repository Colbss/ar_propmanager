<script setup lang="ts">
import { ref, computed, reactive, onMounted } from 'vue'
import { useDraggable } from '@vueuse/core'
import { useAddPropStore } from '../stores/addprop.store'
import { usePropManagerStore } from '../stores/propmanager.store'
import { useApi } from '../composables/useApi'

const addPropStore = useAddPropStore()
const propStore    = usePropManagerStore()

// ─── Draggable ────────────────────────────────────────────────────────────────

const titleBar = ref<HTMLElement | null>(null)
const windowEl = ref<HTMLElement | null>(null)

const { style } = useDraggable(windowEl, {
  handle: titleBar,
  initialValue: {
    x: Math.max(0, (window.innerWidth - Math.min(520, Math.max(380, window.innerWidth * 0.30))) / 2),
    y: Math.round(window.innerHeight * 0.15),
  },
})

// ─── Prop list ────────────────────────────────────────────────────────────────

const propList     = ref<string[]>([])
const listLoading  = ref(true)

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

const searchQuery  = ref('')
const showResults  = ref(false)

function scoreMatch(query: string, target: string): number {
  const q = query.toLowerCase()
  const t = target.toLowerCase()

  if (t === q) return 100
  if (t.startsWith(q)) return 80
  if (t.includes(q)) return 60

  // Segment-level matching (e.g. "bench" matches segments of "prop_bench_01a")
  const qSegs = q.split(/[_\s-]+/).filter(Boolean)
  const tSegs = t.split(/[_\s-]+/)
  let segScore = 0
  for (const qs of qSegs) {
    if (tSegs.some((ts) => ts.startsWith(qs))) segScore += 20
    else if (t.includes(qs)) segScore += 10
  }
  if (segScore > 0) return segScore

  // Fuzzy: all chars of query appear in order within target
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
  // Slight delay so mousedown on a result fires first
  setTimeout(() => { showResults.value = false }, 150)
}

// ─── Form state ───────────────────────────────────────────────────────────────

const existingGroups = computed(() => [...propStore.groups.keys()])

const form = reactive({
  group:         '',
  renderDistance: 200,
  hasExpiry:     false,
  expiresAt:     '',
})

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
        model:         searchQuery.value.trim(),
        group:         form.group.trim(),
        renderDistance: form.renderDistance,
        expiresAt:     form.hasExpiry && form.expiresAt
          ? Math.floor(new Date(form.expiresAt).getTime() / 1000)
          : null,
      }),
    },
    undefined,
    {}
  )

  placing.value = false
  addPropStore.isVisible = false
}
</script>

<template>
  <Transition name="window-fade">
    <div
      ref="windowEl"
      :style="style"
      class="fixed z-30 flex w-[clamp(380px,30vw,520px)] flex-col overflow-visible rounded-xl border border-white/10 bg-black/85 text-white shadow-2xl"
    >
      <!-- Title bar -->
      <div
        ref="titleBar"
        class="flex cursor-grab select-none items-center justify-between border-b border-white/10 px-4 py-2.5 active:cursor-grabbing"
      >
        <div class="flex items-center gap-2 text-sm font-semibold text-slate-200">
          <i class="pi pi-plus-circle text-slate-400" />
          Add Prop
        </div>
        <button class="rounded p-1 text-slate-500 transition hover:text-slate-200" @click="addPropStore.isVisible = false">
          <i class="pi pi-times text-xs" />
        </button>
      </div>

      <!-- Form -->
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
              <div
                v-if="listLoading"
                class="px-3 py-2 text-xs text-slate-500"
              >Loading prop list…</div>
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
            <input
              v-model="form.group"
              list="add-prop-groups"
              type="text"
              placeholder="Select or type group…"
              class="rounded border border-white/10 bg-white/5 px-2.5 py-1.5 text-xs text-slate-100 outline-none transition placeholder:text-slate-600 focus:border-white/25 focus:bg-white/10"
            />
            <datalist id="add-prop-groups">
              <option v-for="g in existingGroups" :key="g" :value="g" />
            </datalist>
          </div>

          <div class="flex flex-col gap-1.5">
            <label class="text-xs font-medium text-slate-400">Render Distance (m)</label>
            <input
              v-model.number="form.renderDistance"
              type="number"
              min="10"
              max="2000"
              step="10"
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
            @click="addPropStore.isVisible = false"
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
