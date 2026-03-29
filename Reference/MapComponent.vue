<script setup lang="ts">
import { ref, onMounted, watch, computed } from 'vue'
import { LMap, LTileLayer } from '@vue-leaflet/vue-leaflet'
import 'leaflet/dist/leaflet.css'
import L from 'leaflet'
import { useTaxStore, type MapType } from '../stores/tax.store'
import ZonePolygons from './ZonePolygons.vue'
import ZonePreview from './ZonePreview.vue'

const taxStore = useTaxStore()
const zoom = ref(2)
const center = ref([0, 0])
const mapRef = ref()

const mapTypes: { value: MapType; label: string; description: string }[] = [
  { value: 'game', label: 'Game', description: 'In-game map style' },
  { value: 'render', label: 'Render', description: 'High quality render' },
  { value: 'print', label: 'Print', description: 'Print-ready version' }
]

// GTA V map configuration
const tileLayerOptions = {
  maxZoom: 7,
  minZoom: 2,
  bounds: L.latLngBounds(L.latLng(0.0, 128.0), L.latLng(-192.0, 0.0)),
}

const mapOptions = {
  crs: L.CRS.Simple,
  maxBoundsViscosity: 1.0,
  preferCanvas: true,
  zoomControl: false,
  attributionControl: false,
}

// Dynamic background color based on map type
const mapBackgroundColor = computed(() => {
  switch (taxStore.currentMapType) {
    case 'game':
      return '#384950'
    case 'render':
      return '#0d2b4f'
    case 'print':
      return '#4eb1d0'
    default:
      return '#000'
  }
})

// Force tile layer refresh when map type changes
const tileLayerKey = ref(0)
watch(() => taxStore.currentMapType, () => {
  tileLayerKey.value++
  // Force background color update
  updateMapBackground()
})

const updateMapBackground = () => {
  if (mapRef.value?.leafletObject) {
    const mapContainer = mapRef.value.leafletObject.getContainer()
    if (mapContainer) {
      mapContainer.style.backgroundColor = mapBackgroundColor.value
    }
  }
}

const selectMapType = (type: MapType) => {
  taxStore.setMapType(type)
}

onMounted(() => {
  // Fix for default markers
  delete (L.Icon.Default.prototype as any)._getIconUrl
  L.Icon.Default.mergeOptions({
    iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon-2x.png',
    iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon.png',
    shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
  })

  // Set initial background color and map bounds after map is ready
  setTimeout(() => {
    updateMapBackground()
    if (mapRef.value?.leafletObject) {
      const bounds = L.latLngBounds(L.latLng(0.0, 128.0), L.latLng(-192.0, 0.0))
      mapRef.value.leafletObject.setMaxBounds(bounds)
      mapRef.value.leafletObject.setView([0, 0], 2)
      
      // Store map instance in the store
      taxStore.setMapInstance(mapRef.value)
    }
  }, 100)
})
</script>

<template>
  <div class="map-container">
    <!-- Map Type Selector Overlay -->
    <div class="map-overlay">
      <div class="map-type-selector-overlay">
        <button
          v-for="mapType in mapTypes"
          :key="mapType.value"
          :class="['map-type-btn-overlay', { active: taxStore.currentMapType === mapType.value }]"
          @click="selectMapType(mapType.value)"
          :title="mapType.description"
        >
          {{ mapType.label }}
        </button>
      </div>
    </div>

    <LMap
      ref="mapRef"
      v-model:zoom="zoom"
      v-model:center="center"
      :options="mapOptions"
      :max-zoom="7"
      :min-zoom="2"
      class="map"
      @ready="updateMapBackground"
    >
      <LTileLayer
        :key="tileLayerKey"
        :url="taxStore.mapTypeUrl"
        :options="tileLayerOptions"
      />
      <ZonePolygons />
      <ZonePreview />
    </LMap>
  </div>
</template>

<style scoped>
.map-container {
  width: 100%;
  height: 100%;
  border-radius: 8px;
  overflow: hidden;
  position: relative;
  background-color: v-bind(mapBackgroundColor);
}

.map {
  width: 100%;
  height: 100%;
  z-index: 1;
}

/* Fallback styling for leaflet container */
.map :deep(.leaflet-container) {
  background-color: v-bind(mapBackgroundColor) !important;
  transition: background-color 0.3s ease;
}

.map :deep(.leaflet-tile-pane) {
  background-color: v-bind(mapBackgroundColor);
}

.map-overlay {
  position: absolute;
  top: 16px;
  right: 16px;
  z-index: 1000;
  pointer-events: none;
}

.map-type-selector-overlay {
  display: flex;
  gap: 6px;
  background: rgba(0, 0, 0, 0.7);
  backdrop-filter: blur(8px);
  border-radius: 8px;
  padding: 8px;
  border: 1px solid rgba(255, 255, 255, 0.1);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
  pointer-events: all;
}

.map-type-btn-overlay {
  background: rgba(255, 255, 255, 0.1);
  border: 1px solid rgba(255, 255, 255, 0.2);
  color: #cccccc;
  padding: 6px 12px;
  border-radius: 4px;
  cursor: pointer;
  font-size: 0.75rem;
  font-weight: 500;
  transition: all 0.2s ease;
  min-width: 50px;
  text-align: center;
}

.map-type-btn-overlay:hover {
  background: rgba(255, 255, 255, 0.2);
  border-color: rgba(255, 255, 255, 0.4);
  color: #ffffff;
  transform: translateY(-1px);
}

.map-type-btn-overlay.active {
  background: rgba(59, 130, 246, 0.8);
  border-color: rgba(59, 130, 246, 1);
  color: #ffffff;
  box-shadow: 0 0 12px rgba(59, 130, 246, 0.5);
}

.map-type-btn-overlay.active:hover {
  background: rgba(59, 130, 246, 0.9);
  transform: translateY(-1px);
}
</style>
