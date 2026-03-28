import React from "react";

interface SimpleOverlayProps {
  modeKey: string;
  focusKey: string;
  finishKey: string;
  cancelKey: string;
}

export const SimpleOverlay: React.FC<SimpleOverlayProps> = ({
  modeKey,
  focusKey,
  finishKey,
  cancelKey,
}) => {
  return (
    <div className="simple-overlay">
      <div>
        <span className="simple-overlay-key" >{modeKey}</span>
        <span>Toggle Move/Rotate</span>
      </div>
      <div>
        <span className="simple-overlay-key" >{focusKey}</span>
        <span>Focus</span>
      </div>
      <div>
        <span className="simple-overlay-key" >{finishKey}</span>
        <span>Done</span>
      </div>
      <div>
        <span className="simple-overlay-key" >{cancelKey}</span>
        <span>Cancel</span>
      </div>
    </div>
  );
};
