<script setup lang="ts">
import { ref } from 'vue'
import { usePropManagerStore } from '../stores/propmanager.store'
import { useAddPropStore } from '../stores/addprop.store'

const props = defineProps<{ canManage: boolean }>()

const store = usePropManagerStore()
const addPropStore = useAddPropStore()

// ─── Group collapse state (persisted in store) ────────────────────────────────

// ─── Helpers ──────────────────────────────────────────────────────────────────

type PropPosition = { x: number; y: number; z: number }

const fmtPos = (p: PropPosition) =>
  `${p.x.toFixed(1)},  ${p.y.toFixed(1)},  ${p.z.toFixed(1)}`

const fmtExpiry = (epoch: number) => {
  const d = new Date(epoch * 1000)
  const dd   = String(d.getDate()).padStart(2, '0')
  const mm   = String(d.getMonth() + 1).padStart(2, '0')
  const yyyy = d.getFullYear()
  const hh   = String(d.getHours()).padStart(2, '0')
  const min  = String(d.getMinutes()).padStart(2, '0')
  return `${dd}/${mm}/${yyyy} ${hh}:${min}`
}

const pendingDelete = ref<number | null>(null)

const requestDelete = (id: number) => {
  if (pendingDelete.value === id) {
    store.deleteProp(id)
    pendingDelete.value = null
  } else {
    pendingDelete.value = id
  }
}

const cancelDelete = () => {
  pendingDelete.value = null
}

const isGroupEnabled = (name: string) => store.groupStates[name] !== false
</script>

<template>
  <div class="flex flex-col" @mousedown="cancelDelete">
    <!-- Toolbar -->
    <div v-if="props.canManage" class="flex items-center justify-end border-b border-white/10 px-3 py-1.5">
      <button
        class="flex items-center gap-1.5 rounded bg-blue-600/70 px-2.5 py-1 text-xs font-medium text-white transition hover:bg-blue-500/80"
        @click.stop="addPropStore.isVisible = true"
      >
        <i class="pi pi-plus text-[0.7rem]" />
        Add Prop
      </button>
    </div>

    <!-- Prop list -->
    <div class="max-h-[45vh] overflow-y-auto">
      <div v-if="store.groups.size === 0" class="py-8 text-center text-xs text-slate-500">
        No props found.
      </div>

      <div v-for="[groupName, groupProps] in store.groups" :key="groupName">
        <!-- Group header -->
        <div
          class="flex w-full items-center border-b border-white/5 bg-white/5 px-3 py-2 text-xs"
          :class="{ 'opacity-50': !isGroupEnabled(groupName) }"
        >
          <!-- Collapse toggle -->
          <button
            class="flex flex-1 items-center gap-2 text-left font-semibold uppercase tracking-wider text-slate-400 transition hover:text-slate-200"
            @click.stop="store.toggleCollapsed(groupName)"
          >
            <i
              :class="store.collapsedGroups.has(groupName) ? 'pi-chevron-right' : 'pi-chevron-down'"
              class="pi text-[0.7rem] text-slate-500"
            />
            {{ groupName }}
            <span class="rounded-full bg-white/10 px-1.5 py-0.5 text-[0.7rem] font-normal text-slate-400">
              {{ groupProps.length }}
            </span>
          </button>

          <!-- Group state badge + toggle -->
          <div class="flex shrink-0 items-center gap-1.5">
            <span
              class="rounded px-1.5 py-0.5 text-[0.7rem] font-medium"
              :class="isGroupEnabled(groupName)
                ? 'bg-green-500/15 text-green-400'
                : 'bg-white/5 text-slate-500'"
            >
              {{ isGroupEnabled(groupName) ? 'Active' : 'Inactive' }}
            </span>
            <button
              class="rounded p-1 transition hover:bg-white/10"
              :class="isGroupEnabled(groupName) ? 'text-green-400 hover:text-green-300' : 'text-slate-500 hover:text-slate-300'"
              :title="isGroupEnabled(groupName) ? 'Disable group (despawn all props)' : 'Enable group (spawn all props)'"
              @click.stop="store.toggleGroup(groupName, !isGroupEnabled(groupName))"
            >
              <i class="pi pi-power-off text-xs" />
            </button>
          </div>
        </div>

        <!-- Prop rows -->
        <template v-if="!store.collapsedGroups.has(groupName)">
          <div
            v-for="prop in groupProps"
            :key="prop.id"
            class="flex items-center gap-2 border-b border-white/5 px-4 py-2 text-xs transition"
            :class="[
              isGroupEnabled(groupName) ? 'hover:bg-white/5' : 'opacity-40',
              prop.outlined ? 'bg-yellow-500/5 ring-1 ring-inset ring-yellow-500/20' : '',
            ]"
          >

            <!-- Model + position stacked -->
            <div class="flex min-w-0 flex-1 flex-col gap-0.5">
              <span class="truncate font-mono text-xs text-slate-200" :title="prop.model">
                {{ prop.model }}
              </span>
              <span class="truncate font-mono text-[0.7rem] text-slate-500" :title="fmtPos(prop.position)">
                {{ fmtPos(prop.position) }}
              </span>
            </div>

            <!-- Expiry + actions -->
            <div class="flex shrink-0 items-center gap-2">
              <span
                v-if="prop.expiresAt"
                class="rounded px-1.5 py-0.5 text-[0.7rem]"
                :class="prop.expiresAt * 1000 < Date.now()
                  ? 'bg-red-500/20 text-red-400'
                  : 'bg-amber-500/15 text-amber-400'"
                :title="'Expires: ' + fmtExpiry(prop.expiresAt)"
              >
                <i class="pi pi-clock mr-0.5 text-[0.6rem]" />{{ fmtExpiry(prop.expiresAt) }}
              </span>

              <div class="flex items-center gap-1">
              <!-- Teleport -->
              <button
                class="rounded px-2 py-1 text-slate-400 transition hover:bg-white/10 hover:text-slate-100"
                :disabled="!isGroupEnabled(groupName)"
                title="Teleport to prop"
                @click.stop="store.teleport(prop.id)"
              >
                <i class="pi pi-map-marker text-xs" />
              </button>

              <!-- Outline -->
              <button
                class="rounded px-2 py-1 transition hover:bg-white/10"
                :disabled="!isGroupEnabled(groupName)"
                :class="prop.outlined ? 'text-yellow-400 hover:text-yellow-300' : 'text-slate-400 hover:text-slate-100'"
                title="Toggle outline"
                @click.stop="store.outline(prop.id)"
              >
                <i class="pi pi-eye text-xs" />
              </button>

              <!-- Delete (manage only) -->
              <button
                v-if="props.canManage"
                class="rounded px-2 py-1 transition hover:bg-white/10"
                :class="pendingDelete === prop.id ? 'text-red-400 hover:text-red-300' : 'text-slate-400 hover:text-slate-100'"
                :title="pendingDelete === prop.id ? 'Click again to confirm delete' : 'Delete prop'"
                @mousedown.stop
                @click.stop="requestDelete(prop.id)"
              >
                <i class="pi text-xs" :class="pendingDelete === prop.id ? 'pi-exclamation-triangle' : 'pi-trash'" />
              </button>
              </div>
            </div>
          </div>
        </template>
      </div>
    </div>

    <!-- Footer: total count -->
    <div class="border-t border-white/5 px-4 py-1.5 text-[0.7rem] text-slate-600">
      {{ store.props.length }} prop{{ store.props.length !== 1 ? 's' : '' }} across {{ store.groups.size }} group{{ store.groups.size !== 1 ? 's' : '' }}
    </div>
  </div>
</template>
