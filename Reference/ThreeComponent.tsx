import { Canvas } from "@react-three/fiber";
import { CameraComponent } from "./CameraComponent";
import { TransformComponent } from "./TransformComponent";
import { Overlay } from "./Overlay";
import { useState } from "react";

export const ThreeComponent = () => {
  const [editorMode, setEditorMode] = useState<"translate" | "rotate">("translate");
  const [spaceMode, setSpaceMode] = useState<"world" | "local">("world");
  const [showOverlay, setShowOverlay] = useState<boolean>(false);
  const [modeKey, setModeKey] = useState<string>("R");
  const [focusKey, setFocusKey] = useState<string>("F");
  const [finishKey, setFinishKey] = useState<string>("E");
  const [cancelKey, setCancelKey] = useState<string>("Back");
  const [attachingProp, setAttachingProp] = useState<boolean>(false);

  return (
    <div style={{ width: "100vw", height: "100vh", position: "relative" }}>
      {/* Keybinds Overlay */}
        <Overlay 
          showOverlay={showOverlay} 
          editorMode={editorMode} 
          spaceMode={spaceMode} 
          setSpaceMode={setSpaceMode}
          modeKey={modeKey} 
          focusKey={focusKey} 
          attachingProp={attachingProp}
        />


      {/* 3D Scene */}
      <Canvas style={{ zIndex: 1 }}>
        <CameraComponent />
        <TransformComponent 
          setEditorMode={setEditorMode} 
          setSpaceMode={setSpaceMode} 
          setShowOverlay={setShowOverlay}
          setModeKey={setModeKey}
          setFocusKey={setFocusKey}
          setFinishKey={setFinishKey}
          setCancelKey={setCancelKey}
          spaceMode={spaceMode} 
          setAttachingProp={setAttachingProp}
        />
      </Canvas>
    </div>
  );
};
