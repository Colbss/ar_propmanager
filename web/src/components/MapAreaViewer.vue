<script setup lang="ts">
import { ref, watch, onUnmounted, nextTick } from 'vue'
import type { AreaRestriction } from '../stores/playeraccess.store'
import type { Map as LeafletMap, Polygon, CircleMarker } from 'leaflet'

const props = defineProps<{
  area: AreaRestriction | null
  height?: string
}>()

// ─── GTA V ↔ Leaflet coordinate conversion ───────────────────────────────────

const MAP_CENTER: [number, number] = [-119.43, 58.84]
const LAT_PER_100 = 1.421

function gameToMap(x: number, y: number): [number, number] {
  return [
    MAP_CENTER[0] + (LAT_PER_100 / 100) * y,
    MAP_CENTER[1] + (LAT_PER_100 / 100) * x,
  ]
}

function circlePolygon(cx: number, cy: number, r: number, n = 80): [number, number][] {
  return Array.from({ length: n }, (_, i) => {
    const a = (2 * Math.PI * i) / n
    return gameToMap(cx + r * Math.cos(a), cy + r * Math.sin(a))
  })
}

// ─── State ────────────────────────────────────────────────────────────────────

const mapContainer = ref<HTMLElement | null>(null)
let L: typeof import('leaflet') | null = null
let map: LeafletMap | null = null
let shape: Polygon | null = null
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

  L.tileLayer(TILE_URL, {
    maxZoom: 7,
    minZoom: 2,
    bounds,
    noWrap: true,
  }).addTo(map)

  L.control.zoom({ position: 'bottomright' }).addTo(map)

  redraw()
}

// ─── Drawing ──────────────────────────────────────────────────────────────────

function redraw() {
  if (!L || !map) return

  if (shape) { shape.remove(); shape = null }
  if (centerMarker) { centerMarker.remove(); centerMarker = null }

  const area = props.area
  if (!area) return

  if (area.type === 'radius') {
    const pts = circlePolygon(area.center.x, area.center.y, area.radius)
    shape = L.polygon(pts, {
      color: '#3b82f6',
      fillColor: '#3b82f6',
      fillOpacity: 0.18,
      weight: 2,
    }).addTo(map)

    centerMarker = L.circleMarker(gameToMap(area.center.x, area.center.y), {
      radius: 5,
      color: '#60a5fa',
      fillColor: '#93c5fd',
      fillOpacity: 1,
      weight: 2,
    }).addTo(map)

    map.fitBounds(shape.getBounds(), { padding: [24, 24] })
  } else if (area.type === 'zone' && area.points.length >= 2) {
    const latlngs = area.points.map((p) => gameToMap(p.x, p.y))
    shape = L.polygon(latlngs as [number, number][], {
      color: '#3b82f6',
      fillColor: '#3b82f6',
      fillOpacity: area.points.length >= 3 ? 0.18 : 0,
      weight: 2,
    }).addTo(map)

    map.fitBounds(shape.getBounds(), { padding: [24, 24] })
  }
}

// ─── Lifecycle ────────────────────────────────────────────────────────────────

watch(
  () => mapContainer.value,
  (el) => { if (el) nextTick(initMap) },
  { immediate: true },
)

watch(() => props.area, redraw, { deep: true })

onUnmounted(() => {
  map?.remove()
  map = null
})
</script>

<template>
  <div class="overflow-hidden rounded border border-white/10 bg-black/30">
    <div ref="mapContainer" :style="{ height: height ?? '18vh' }" class="w-full" />
  </div>
</template>
