<script setup lang="ts">
import { ref, watch, onUnmounted, nextTick } from 'vue'
import { useApi } from '../composables/useApi'
import type { RadiusArea } from '../stores/playeraccess.store'
import type { Map as LeafletMap, Polygon, CircleMarker } from 'leaflet'

const props = defineProps<{
  modelValue: RadiusArea | null
}>()

const emit = defineEmits<{
  'update:modelValue': [value: RadiusArea | null]
}>()

// ─── Internal state ───────────────────────────────────────────────────────────

const center      = ref<{ x: number; y: number } | null>(
  props.modelValue ? { x: props.modelValue.center.x, y: props.modelValue.center.y } : null
)
const radiusInput = ref(props.modelValue ? String(props.modelValue.radius) : '50')

function commit() {
  if (!center.value) { emit('update:modelValue', null); return }
  const r = parseFloat(radiusInput.value)
  if (isNaN(r) || r <= 0) { emit('update:modelValue', null); return }
  emit('update:modelValue', {
    type: 'radius',
    center: { x: center.value.x, y: center.value.y },
    radius: r,
  })
}

// ─── GTA V ↔ Leaflet coordinate conversion ───────────────────────────────────

const MAP_CENTER: [number, number] = [-119.43, 58.84]
const LAT_PER_100 = 1.421

function gameToMap(x: number, y: number): [number, number] {
  return [
    MAP_CENTER[0] + (LAT_PER_100 / 100) * y,
    MAP_CENTER[1] + (LAT_PER_100 / 100) * x,
  ]
}

function mapToGame(lat: number, lng: number): { x: number; y: number } {
  const scale = LAT_PER_100 / 100
  return {
    x: (lng - MAP_CENTER[1]) / scale,
    y: (lat - MAP_CENTER[0]) / scale,
  }
}

function circlePolygon(cx: number, cy: number, r: number, n = 80): [number, number][] {
  return Array.from({ length: n }, (_, i) => {
    const a = (2 * Math.PI * i) / n
    return gameToMap(cx + r * Math.cos(a), cy + r * Math.sin(a))
  })
}

// ─── Map state ────────────────────────────────────────────────────────────────

const mapContainer = ref<HTMLElement | null>(null)
const hoverCoords  = ref<{ x: number; y: number } | null>(null)

let L: typeof import('leaflet') | null = null
let map: LeafletMap | null = null
let circleShape: Polygon | null = null
let centerMarker: CircleMarker | null = null

const TILE_URL = 'https://s.rsg.sc/sc/images/games/GTAV/map/game/{z}/{x}/{y}.jpg'

// ─── Leaflet bootstrap ────────────────────────────────────────────────────────

async function initMap() {
  if (!mapContainer.value) return

  L = await import('leaflet')
  await import('leaflet/dist/leaflet.css')

  map = L.map(mapContainer.value, {
    crs: L.CRS.Simple,
    maxBoundsViscosity: 1.0,
    preferCanvas: true,
    zoomControl: false,
    attributionControl: false,
    maxZoom: 7,
    minZoom: 2,
  })

  const bounds = L.latLngBounds(L.latLng(0, 128), L.latLng(-192, 0))
  map.setMaxBounds(bounds)
  map.fitBounds(bounds)

  const container = map.getContainer()
  if (container) container.style.backgroundColor = '#384950'

  L.tileLayer(TILE_URL, { maxZoom: 7, minZoom: 2, bounds, noWrap: true }).addTo(map)
  L.control.zoom({ position: 'bottomright' }).addTo(map)

  map.on('click', onMapClick)
  map.on('mousemove', (e) => { hoverCoords.value = mapToGame(e.latlng.lat, e.latlng.lng) })
  map.on('mouseout', () => { hoverCoords.value = null })

  redraw()

  // If editing an existing radius area, zoom to fit the circle
  if (center.value) {
    const r = parseFloat(radiusInput.value) || 50
    const bounds = L.polygon(circlePolygon(center.value.x, center.value.y, r)).getBounds()
    map.fitBounds(bounds, { padding: [24, 24] })
  }
}

// ─── Interaction ──────────────────────────────────────────────────────────────

function onMapClick(e: import('leaflet').LeafletMouseEvent) {
  center.value = mapToGame(e.latlng.lat, e.latlng.lng)
  redraw()
  commit()
}

const clearCenter = () => {
  center.value = null
  redraw()
  commit()
}

// ─── Drawing ──────────────────────────────────────────────────────────────────

function redraw() {
  if (!L || !map) return

  if (circleShape)  { circleShape.remove();  circleShape  = null }
  if (centerMarker) { centerMarker.remove(); centerMarker = null }

  if (!center.value) return

  centerMarker = L.circleMarker(gameToMap(center.value.x, center.value.y), {
    radius: 6, color: '#60a5fa', fillColor: '#93c5fd', fillOpacity: 1, weight: 2,
  }).addTo(map)

  const r = parseFloat(radiusInput.value)
  if (!isNaN(r) && r > 0) {
    circleShape = L.polygon(circlePolygon(center.value.x, center.value.y, r), {
      color: '#3b82f6', fillColor: '#3b82f6', fillOpacity: 0.18, weight: 2,
    }).addTo(map)
  }
}

watch(radiusInput, () => { redraw(); commit() })

// ─── Use my position ──────────────────────────────────────────────────────────

const fetchingPos = ref(false)

const useMyPosition = async () => {
  fetchingPos.value = true
  const result = await useApi<{ x: number; y: number }>(
    'GetPlayerPosition',
    { method: 'POST', body: JSON.stringify({}) },
    undefined,
    { x: 215.4, y: -810.2 },
  )
  if (result.data.value) {
    const pos = result.data.value
    center.value = { x: pos.x, y: pos.y }
    redraw()
    commit()
    if (map) {
      const r = parseFloat(radiusInput.value) || 50
      const bounds = L!.polygon(circlePolygon(pos.x, pos.y, r)).getBounds()
      map.fitBounds(bounds, { padding: [24, 24] })
    }
  }
  fetchingPos.value = false
}

// ─── Lifecycle ────────────────────────────────────────────────────────────────

watch(
  () => mapContainer.value,
  (el) => { if (el) nextTick(initMap) },
  { immediate: true },
)

onUnmounted(() => {
  map?.remove()
  map = null
})
</script>

<template>
  <div class="overflow-hidden rounded border border-white/10 bg-black/30">
    <!-- Top bar: hover coords + center readout + clear -->
    <div class="flex h-7 items-center justify-between border-b border-white/10 bg-black/40 px-3">
      <span class="font-mono text-[0.7rem] text-slate-500">
        <template v-if="hoverCoords">
          X {{ hoverCoords.x.toFixed(0) }}&nbsp;&nbsp;Y {{ hoverCoords.y.toFixed(0) }}
        </template>
        <template v-else-if="center">
          Center: {{ center.x.toFixed(1) }}, {{ center.y.toFixed(1) }}
        </template>
        <template v-else>
          Click map to place center
        </template>
      </span>
      <button
        v-if="center"
        class="rounded px-1.5 py-0.5 text-[0.7rem] text-slate-500 transition hover:text-red-400"
        @click.stop="clearCenter"
      >
        <i class="pi pi-times text-[0.6rem]" /> Clear
      </button>
    </div>

    <!-- Map -->
    <div ref="mapContainer" class="h-[26vh] w-full" />

    <!-- Bottom bar: Radius · Use My Position -->
    <div class="flex items-center gap-3 border-t border-white/10 bg-black/40 px-3 py-1.5">
      <div class="flex items-center gap-1.5">
        <span class="text-[0.7rem] text-slate-400">Radius (m)</span>
        <input
          v-model="radiusInput"
          type="text"
          placeholder="50"
          class="w-16 rounded border border-white/10 bg-black/40 px-1.5 py-0.5 font-mono text-xs text-slate-100 outline-none focus:border-white/25"
        />
      </div>
      <button
        class="ml-auto flex items-center gap-1 rounded bg-white/10 px-2 py-0.5 text-xs text-slate-300 transition hover:bg-white/20 disabled:opacity-40"
        :disabled="fetchingPos"
        @click.stop="useMyPosition"
      >
        <i class="pi pi-map-marker text-[0.7rem]" />
        {{ fetchingPos ? 'Fetching…' : 'Use My Position' }}
      </button>
    </div>
  </div>
</template>
