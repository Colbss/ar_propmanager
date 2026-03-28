<script setup lang="ts">
import { ref } from 'vue'
import { usePropManagerStore } from '../stores/propmanager.store'

const store = usePropManagerStore()

// ─── Group collapse state ─────────────────────────────────────────────────────

const collapsed = ref(new Set<string>())

const toggleCollapse = (name: string) => {
  if (collapsed.value.has(name)) collapsed.value.delete(name)
  else collapsed.value.add(name)
  collapsed.value = new Set(collapsed.value)
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

type PropPosition = { x: number; y: number; z: number }

const fmtPos = (p: PropPosition) =>
  `${p.x.toFixed(1)},  ${p.y.toFixed(1)},  ${p.z.toFixed(1)}`

const pendingDelete = ref<string | null>(null)

const requestDelete = (id: string) => {
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
    <!-- Prop list -->
    <div class="max-h-[480px] overflow-y-auto">
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
            @click.stop="toggleCollapse(groupName)"
          >
            <i
              :class="collapsed.has(groupName) ? 'pi-chevron-right' : 'pi-chevron-down'"
              class="pi text-[10px] text-slate-500"
            />
            {{ groupName }}
            <span class="rounded-full bg-white/10 px-1.5 py-0.5 text-[10px] font-normal text-slate-400">
              {{ groupProps.length }}
            </span>
          </button>

          <!-- Group state badge + toggle -->
          <div class="flex shrink-0 items-center gap-1.5">
            <span
              class="rounded px-1.5 py-0.5 text-[10px] font-medium"
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
              <i class="pi pi-power-off text-[11px]" />
            </button>
          </div>
        </div>

        <!-- Prop rows -->
        <template v-if="!collapsed.has(groupName)">
          <div
            v-for="prop in groupProps"
            :key="prop.id"
            class="flex items-center gap-2 border-b border-white/5 px-4 py-2 text-xs transition"
            :class="[
              isGroupEnabled(groupName) ? 'hover:bg-white/5' : 'opacity-40',
              prop.outlined ? 'bg-yellow-500/5 ring-1 ring-inset ring-yellow-500/20' : '',
            ]"
          >

            <!-- Model name -->
            <span class="w-44 shrink-0 truncate font-mono text-slate-200" :title="prop.model">
              {{ prop.model }}
            </span>

            <!-- Position -->
            <span class="flex-1 truncate font-mono text-[11px] text-slate-500" :title="fmtPos(prop.position)">
              {{ fmtPos(prop.position) }}
            </span>

            <!-- Actions -->
            <div class="flex shrink-0 items-center gap-1">
              <!-- Teleport -->
              <button
                class="rounded px-2 py-1 text-slate-400 transition hover:bg-white/10 hover:text-slate-100"
                :disabled="!isGroupEnabled(groupName)"
                title="Teleport to prop"
                @click.stop="store.teleport(prop.id)"
              >
                <i class="pi pi-map-marker text-[11px]" />
              </button>

              <!-- Outline -->
              <button
                class="rounded px-2 py-1 transition hover:bg-white/10"
                :disabled="!isGroupEnabled(groupName)"
                :class="prop.outlined ? 'text-yellow-400 hover:text-yellow-300' : 'text-slate-400 hover:text-slate-100'"
                title="Toggle outline"
                @click.stop="store.outline(prop.id)"
              >
                <i class="pi pi-eye text-[11px]" />
              </button>

              <!-- Delete -->
              <button
                class="rounded px-2 py-1 transition hover:bg-white/10"
                :class="pendingDelete === prop.id ? 'text-red-400 hover:text-red-300' : 'text-slate-400 hover:text-slate-100'"
                :title="pendingDelete === prop.id ? 'Click again to confirm delete' : 'Delete prop'"
                @click.stop="requestDelete(prop.id)"
              >
                <i class="pi text-[11px]" :class="pendingDelete === prop.id ? 'pi-exclamation-triangle' : 'pi-trash'" />
              </button>
            </div>
          </div>
        </template>
      </div>
    </div>

    <!-- Footer: total count -->
    <div class="border-t border-white/5 px-4 py-1.5 text-[10px] text-slate-600">
      {{ store.props.length }} prop{{ store.props.length !== 1 ? 's' : '' }} across {{ store.groups.size }} group{{ store.groups.size !== 1 ? 's' : '' }}
    </div>
  </div>
</template>
