import React from "react";
import { fetchNui } from "../nui-events";
interface OverlayProps {
  showOverlay: boolean;
  editorMode: "translate" | "rotate";
  spaceMode: "world" | "local";
  setSpaceMode: (mode: "world" | "local") => void;
  modeKey: string;
  focusKey: string;
  attachingProp: boolean;
}

export const Overlay: React.FC<OverlayProps> = ({ showOverlay, editorMode, spaceMode, setSpaceMode, modeKey, focusKey, attachingProp }) => {
  if (!showOverlay) return null;

  return (
    <div className="overlay">
      <div className="header">Gizmo Controls</div>

      <div className='divider'></div>

      <div className="modes">
        <fieldset>
          <legend>Edit Mode</legend>
          {editorMode === "translate" ? "Translate" : "Rotate"}
        </fieldset>
        <fieldset>
          <legend>Axis Space</legend>
          {spaceMode === "world" ? "World" : "Local"}
        </fieldset>
      </div>

      <div className="hotkeys-container">
        <div className="hotkeys">
          <div className="hotkey">
            <div className="key">{modeKey}</div>
            Toggle Edit Mode
          </div>

          <div className="hotkey">
            <div className="key">{focusKey}</div>
            Toggle Focus
          </div>
        </div>
      </div>

      <div className='divider'></div>
      <div className="button-group">
        <button onClick={() => setSpaceMode(spaceMode === "world" ? "local" : "world")}>
            Toggle Axis Space
        </button>
        
        {!attachingProp && (
          <>
            <button onClick={() => fetchNui("SnapToGround")}>Snap To Ground</button>
            <button onClick={() => fetchNui("ResetRotation")}>Reset Rotation</button>
          </>
        )}

        <div className='divider'></div>
        <button onClick={() => fetchNui("Finish")} className="btn-blue">Done</button>
        <button onClick={() => fetchNui("Cancel")} className="btn-red">Cancel</button>
      </div>
    </div>
  );
};
