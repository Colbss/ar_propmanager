import { Suspense, useRef, useState, useEffect } from "react";
import { TransformControls } from "@react-three/drei";
import { useNuiEvent, fetchNui } from "../nui-events";
import { Mesh, Quaternion, Euler } from "three";

interface TransformComponentProps {
  setEditorMode: (mode: "translate" | "rotate") => void;
  setSpaceMode: (mode: "world" | "local") => void;
  setShowOverlay: (visible: boolean) => void;
  setModeKey: (key: string) => void;
  setFocusKey: (key: string) => void;
  setFinishKey: (key: string) => void;
  setCancelKey: (key: string) => void;
  spaceMode: "world" | "local"; 
  setAttachingProp: (attaching: boolean) => void;
}

export const TransformComponent: React.FC<TransformComponentProps> = ({ 
  setEditorMode, 
  setSpaceMode, 
  setShowOverlay, 
  setModeKey, 
  setFocusKey,
  setFinishKey,
  setCancelKey,
  spaceMode,
  setAttachingProp,
}) => {
  const mesh = useRef<Mesh>(null!);
  const [currentEntity, setCurrentEntity] = useState<number>();
  const [editorMode, setMode] = useState<"translate" | "rotate">("translate");
  const [modeKey, setModeKeyState] = useState<string>("R");
  const [focusKey, setFocusKeyState] = useState<string>("F");
  const [finishKey, setFinishKeyState] = useState<string>("E");
  const [cancelKey, setCancelKeyState] = useState<string>("Back");
  const [restrictRotationAxes, setRestrictRotationAxes] = useState<boolean>(false);
  const [returnEuler, setReturnEuler] = useState<boolean>(false);

  const currentModeKey = useRef<string>(modeKey);
  const currentFocusKey = useRef<string>(focusKey);
  const currentFinishKey = useRef<string>(finishKey);
  const currentCancelKey = useRef<string>(cancelKey);

  useEffect(() => {
    currentModeKey.current = modeKey;
    currentFocusKey.current = focusKey;
    currentFinishKey.current = finishKey;
    currentCancelKey.current = cancelKey;
  }, [modeKey, focusKey, finishKey, cancelKey]);

  const handleObjectDataUpdate = () => {
    const quaternion = mesh.current.quaternion;
    const euler = new Euler().setFromQuaternion(quaternion, "YZX");

    fetchNui("MoveEntity", {
      handle: currentEntity,
      position: { x: mesh.current.position.x, y: -mesh.current.position.z, z: mesh.current.position.y },
      ...(returnEuler 
        ? { rotation: { x: euler.x * (180 / Math.PI), y: -euler.z * (180 / Math.PI), z: euler.y * (180 / Math.PI) } }
        : { quaternion: { x: quaternion.x, y: -quaternion.z, z: quaternion.y, w: quaternion.w } })
    });
  };

  useNuiEvent("setGizmoEntity", (entity: any) => {
    setCurrentEntity(entity.handle);
    
    if (!entity.handle) {
      setShowOverlay(false);
      return;
    }

    // Convert all key values to strings to ensure consistency
    const modeKeyStr = String(entity.modekey || "R");
    const focusKeyStr = String(entity.focuskey || "F");
    const finishKeyStr = String(entity.finishkey || "E");
    const cancelKeyStr = String(entity.cancelkey || "Back");

    setShowOverlay(true);
    mesh.current.position.set(entity.position.x, entity.position.z, -entity.position.y);

    const newQuaternion = new Quaternion(entity.quaternion.x, entity.quaternion.y, entity.quaternion.z, entity.quaternion.w);
    mesh.current.quaternion.copy(newQuaternion);

    // Set internal component state
    setModeKeyState(modeKeyStr);
    setFocusKeyState(focusKeyStr);
    setFinishKeyState(finishKeyStr);
    setCancelKeyState(cancelKeyStr);
    
    // Set parent component state
    setModeKey(modeKeyStr);
    setFocusKey(focusKeyStr);
    setFinishKey(finishKeyStr);
    setCancelKey(cancelKeyStr);
    
    // Save the keys for event listener checks to avoid React's asynchronous state updates
    // causing issues with key detection
    currentModeKey.current = modeKeyStr;
    currentFocusKey.current = focusKeyStr;
    currentFinishKey.current = finishKeyStr;
    currentCancelKey.current = cancelKeyStr;
    
    setRestrictRotationAxes(entity.restrictRotationAxes || false);
    setReturnEuler(entity.returnEuler || false);
    setAttachingProp(entity.attachingProp || false);
    
    // If simpleOverlay is true, force spaceMode to local
    if (entity.simpleOverlay) {
      setSpaceMode("local");
    }
  });

  useNuiEvent("updateGizmoTransform", (data: any) => {
    if (!currentEntity || currentEntity !== data.handle) return;

    mesh.current.position.set(data.position.x, data.position.z, -data.position.y);
    console.log('UPDATE | X: ' + data.quaternion.x + ' | Y: ' + data.quaternion.y + ' | Z: ' + data.quaternion.z + ' | W: ' + data.quaternion.w)
    const newQuaternion = new Quaternion(data.quaternion.x, data.quaternion.y, data.quaternion.z, data.quaternion.w);
    mesh.current.quaternion.copy(newQuaternion);
  });

  useNuiEvent("closeGizmo", () => {
    setShowOverlay(false);
  });

  useEffect(() => {
    const keyHandler = (e: KeyboardEvent) => {
      // Use the ref values for key matching

      // Change to use native lua keybinds

      // if (isKeyMatch(e, currentModeKey.current)) {
      //   setMode(prev => {
      //     const newMode = prev === "translate" ? "rotate" : "translate";
      //     setEditorMode(newMode);
      //     return newMode;
      //   });
      // }

      // if (isKeyMatch(e, currentFocusKey.current)) {
      //   fetchNui("cam");
      // }

      // if (isKeyMatch(e, currentFinishKey.current)) {
      //   setShowOverlay(false);
      //   fetchNui("Finish");
      // }

      // if (isKeyMatch(e, currentCancelKey.current) || e.code === "Escape") {
      //   setShowOverlay(false);
      //   fetchNui("Cancel");
      // }
    };

    window.addEventListener("keyup", keyHandler);
    return () => window.removeEventListener("keyup", keyHandler);
  }, [editorMode, spaceMode]);

  return (
    <>
      <Suspense fallback={<p>Loading Gizmo</p>}>
        {currentEntity != null && (
          <TransformControls
            size={0.5}
            object={mesh}
            mode={editorMode}
            space={spaceMode} 
            onObjectChange={handleObjectDataUpdate}
            showX={!restrictRotationAxes || editorMode !== "rotate"}
            showZ={!restrictRotationAxes || editorMode !== "rotate"}
          />
        )}
        <mesh ref={mesh} />
      </Suspense>
    </>
  );
};
