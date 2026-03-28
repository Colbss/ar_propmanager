import { defineStore } from 'pinia'
import { ref } from 'vue'
import { useApi } from '../composables/useApi'

export type EditorMode = 'translate' | 'rotate'
export type SpaceMode = 'world' | 'local'

export interface GizmoKey {
  key: string
  description: string
}

export interface GizmoKeys {
  mode: GizmoKey
  focus: GizmoKey
  finish: GizmoKey
  cancel: GizmoKey
}

export const usePMStore = defineStore('pm', () => {
  const isVisible = ref<boolean>(false)
  const showOverlay = ref<boolean>(false)
  const editorMode = ref<EditorMode>('translate')
  const spaceMode = ref<SpaceMode>('world')
  const currentEntity = ref<number | null>(null)
  const keys = ref<GizmoKeys>({
    mode:   { key: 'R',    description: 'Change Mode' },
    focus:  { key: 'F',    description: 'Toggle Focus' },
    finish: { key: 'E',    description: 'Finish' },
    cancel: { key: 'Back', description: 'Cancel' },
  })
  const attachingProp = ref<boolean>(false)
  const simpleOverlay = ref<boolean>(false)
  const restrictRotationAxes = ref<boolean>(false)
  const displayPosition = ref<{ x: number; y: number; z: number }>({ x: 0, y: 0, z: 0 })
  const displayRotation = ref<{ x: number; y: number; z: number }>({ x: 0, y: 0, z: 0 })

  // Set by GizmoOverlay when the user manually commits a value; ThreeScene watches and applies it.
  const manualTransform = ref<{
    position: { x: number; y: number; z: number }
    rotation: { x: number; y: number; z: number }
  } | null>(null)

  const applyManualTransform = (
    position: { x: number; y: number; z: number },
    rotation: { x: number; y: number; z: number }
  ) => {
    manualTransform.value = { position, rotation }
  }

  const updateDisplay = (
    position: { x: number; y: number; z: number },
    rotation: { x: number; y: number; z: number }
  ) => {
    displayPosition.value = position
    displayRotation.value = rotation
  }

  const toggleEditorMode = () => {
    editorMode.value = editorMode.value === 'translate' ? 'rotate' : 'translate'
  }

  const toggleSpaceMode = () => {
    spaceMode.value = spaceMode.value === 'world' ? 'local' : 'world'
  }

  const moveEntity = (handle: number, position: object, quaternion: object) => {
    useApi(
      'MoveEntity',
      { method: 'POST', body: JSON.stringify({ handle, position, quaternion }) },
      undefined,
      {}
    )
  }

  const snapToGround = () => {
    useApi('SnapToGround', { method: 'POST', body: JSON.stringify({}) }, undefined, {})
  }

  const resetRotation = () => {
    useApi('ResetRotation', { method: 'POST', body: JSON.stringify({}) }, undefined, {})
  }

  const finish = () => {
    useApi('Finish', { method: 'POST', body: JSON.stringify({}) }, undefined, {})
  }

  const cancel = () => {
    useApi('Cancel', { method: 'POST', body: JSON.stringify({}) }, undefined, {})
  }

  return {
    isVisible,
    showOverlay,
    editorMode,
    spaceMode,
    currentEntity,
    keys,
    attachingProp,
    simpleOverlay,
    restrictRotationAxes,
    displayPosition,
    displayRotation,
    updateDisplay,
    manualTransform,
    applyManualTransform,
    toggleEditorMode,
    toggleSpaceMode,
    moveEntity,
    snapToGround,
    resetRotation,
    finish,
    cancel,
  }
})
