<script setup lang="ts">
import { onMounted, onUnmounted, ref, watch } from 'vue'
import * as THREE from 'three'
import { TransformControls } from 'three/examples/jsm/controls/TransformControls.js'
import { useNuiEvent } from '../composables/useNuiEvent'
import { useGizmoStore } from '../stores/gizmo.store'

const canvasRef = ref<HTMLCanvasElement | null>(null)
const gizmoStore = useGizmoStore()

let renderer: THREE.WebGLRenderer | null = null
let camera: THREE.PerspectiveCamera
let scene: THREE.Scene
let transformControls: TransformControls
let mesh: THREE.Mesh
let animFrameId: number

// ─── Init ────────────────────────────────────────────────────────────────────

function initThree() {
  if (!canvasRef.value) return

  renderer = new THREE.WebGLRenderer({ canvas: canvasRef.value, alpha: true, antialias: true })
  renderer.setPixelRatio(window.devicePixelRatio)
  renderer.setSize(window.innerWidth, window.innerHeight)
  renderer.setClearColor(0x000000, 0)

  camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.01, 10000)
  camera.position.set(0, 0, 10)

  scene = new THREE.Scene()

  // Invisible placeholder – TransformControls needs an Object3D to attach to
  mesh = new THREE.Mesh(
    new THREE.BoxGeometry(0.001, 0.001, 0.001),
    new THREE.MeshBasicMaterial({ visible: false })
  )
  scene.add(mesh)

  transformControls = new TransformControls(camera, renderer.domElement)
  transformControls.setSize(0.5)
  scene.add(transformControls.getHelper())

  transformControls.addEventListener('objectChange', handleObjectChange)

  animate()
}

function animate() {
  animFrameId = requestAnimationFrame(animate)
  renderer?.render(scene, camera)
}

// ─── Coordinate helpers ───────────────────────────────────────────────────────
// FiveM uses Z-up; Three.js uses Y-up.
// FiveM → Three.js:  (x, y, z) → (x, z, -y)
// Three.js → FiveM:  (x, y, z) → (x, -z, y)
// Quaternion → FiveM: (x, y, z, w) → (x, -z, y, w)

// ─── Transform change handler ─────────────────────────────────────────────────

function syncDisplay() {
  const pos = mesh.position
  const euler = new THREE.Euler().setFromQuaternion(mesh.quaternion, 'YZX')
  const toDeg = THREE.MathUtils.radToDeg
  gizmoStore.updateDisplay(
    { x: pos.x, y: -pos.z, z: pos.y },
    { x: toDeg(euler.x), y: toDeg(-euler.z), z: toDeg(euler.y) }
  )
}

function handleObjectChange() {
  if (!gizmoStore.isVisible || !mesh) return

  const pos = mesh.position
  const quat = mesh.quaternion

  gizmoStore.moveEntity(
    { x: pos.x, y: -pos.z, z: pos.y },
    { x: quat.x, y: -quat.z, z: quat.y, w: quat.w }
  )
  syncDisplay()
}

// ─── NUI Events ───────────────────────────────────────────────────────────────

useNuiEvent<{
  position: { x: number; y: number; z: number }
  quaternion: { x: number; y: number; z: number; w: number }
  keybinds?: { mode: { key: string; description: string }; focus: { key: string; description: string }; finish: { key: string; description: string }; cancel: { key: string; description: string } }
  restrictRotationAxes?: boolean
}>('initGizmo', (entity) => {
  if (!mesh || !transformControls) return

  if (entity.keybinds) gizmoStore.keys = entity.keybinds
  gizmoStore.restrictRotationAxes = entity.restrictRotationAxes ?? false

  mesh.position.set(entity.position.x, entity.position.z, -entity.position.y)
  mesh.quaternion.set(entity.quaternion.x, entity.quaternion.y, entity.quaternion.z, entity.quaternion.w)
  syncDisplay()

  transformControls.attach(mesh)
  gizmoStore.isVisible = true
})

useNuiEvent<{
  position: { x: number; y: number; z: number }
  quaternion: { x: number; y: number; z: number; w: number }
}>('updateGizmoTransform', (data) => {
  if (!mesh || !gizmoStore.isVisible) return

  mesh.position.set(data.position.x, data.position.z, -data.position.y)
  mesh.quaternion.set(data.quaternion.x, data.quaternion.y, data.quaternion.z, data.quaternion.w)
  syncDisplay()
})

useNuiEvent('closeGizmo', () => {
  if (!transformControls) return
  transformControls.detach()
  gizmoStore.isVisible = false
})

useNuiEvent<{
  position: { x: number; y: number; z: number }
  rotation: { x: number; y: number; z: number }
  fov?: number
}>('setCameraPosition', ({ position, rotation, fov }) => {
  if (!camera) return

  camera.position.set(position.x, position.z, -position.y)
  camera.rotation.order = 'YZX'

  // GTA can flip the camera when rotation.x crosses certain thresholds;
  // the Z component needs to be sign-flipped to compensate.
  const zSign = (t: number, e: number) =>
    t > 0 && t < 90 ? e : (t > -180 && t < -90) || t > 0 ? -e : e

  camera.rotation.set(
    THREE.MathUtils.degToRad(rotation.x),
    THREE.MathUtils.degToRad(zSign(rotation.x, rotation.z)),
    THREE.MathUtils.degToRad(rotation.y)
  )

  if (fov) camera.fov = fov
  camera.updateProjectionMatrix()
})

// Toggle edit mode from Lua keybind
useNuiEvent('toggleMode', () => {
  if (!transformControls) return
  gizmoStore.toggleEditorMode()
})

// ─── Watchers ─────────────────────────────────────────────────────────────────

// Reverse of syncDisplay: FiveM (rx,ry,rz) degrees → Three.js Euler 'YZX'
// From syncDisplay: fivem.x=deg(e.x), fivem.y=deg(-e.z), fivem.z=deg(e.y)
// So:               e.x=rad(fivem.x),  e.z=-rad(fivem.y), e.y=rad(fivem.z)
watch(
  () => gizmoStore.manualTransform,
  (transform) => {
    if (!transform || !mesh || !gizmoStore.isVisible) return

    const { position: pos, rotation: rot } = transform
    mesh.position.set(pos.x, pos.z, -pos.y)

    const euler = new THREE.Euler(
      THREE.MathUtils.degToRad(rot.x),
      THREE.MathUtils.degToRad(rot.z),
      -THREE.MathUtils.degToRad(rot.y),
      'YZX'
    )
    const quat = new THREE.Quaternion().setFromEuler(euler)
    mesh.quaternion.copy(quat)

    gizmoStore.moveEntity(
      { x: pos.x, y: pos.y, z: pos.z },
      { x: quat.x, y: -quat.z, z: quat.y, w: quat.w }
    )
    syncDisplay()
    gizmoStore.manualTransform = null
  }
)

watch(
  () => gizmoStore.editorMode,
  (mode) => transformControls?.setMode(mode)
)

watch(
  () => gizmoStore.spaceMode,
  (space) => transformControls?.setSpace(space)
)

watch(
  [() => gizmoStore.restrictRotationAxes, () => gizmoStore.editorMode],
  ([restrict, mode]) => {
    if (!transformControls) return
    const hide = restrict && mode === 'rotate'
    transformControls.showX = !hide
    transformControls.showZ = !hide
  }
)

// ─── Lifecycle ────────────────────────────────────────────────────────────────

onMounted(() => {
  initThree()

  const onResize = () => {
    if (!renderer || !camera) return
    camera.aspect = window.innerWidth / window.innerHeight
    camera.updateProjectionMatrix()
    renderer.setSize(window.innerWidth, window.innerHeight)
  }

  window.addEventListener('resize', onResize)
  onUnmounted(() => window.removeEventListener('resize', onResize))
})

onUnmounted(() => {
  cancelAnimationFrame(animFrameId)
  renderer?.dispose()
})
</script>

<template>
  <canvas
    ref="canvasRef"
    class="absolute inset-0 w-full h-full"
    style="z-index: 1; pointer-events: auto;"
  />
</template>
