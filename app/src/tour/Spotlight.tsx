import { useEffect, useLayoutEffect, useState } from "react";
import { type Box, boxOf, findTarget, holePath, sameBox } from "./target";

export function Spotlight({
  targetKey,
  onBox,
}: {
  targetKey: string | null;
  onBox(box: Box | null): void;
}) {
  const [box, setBox] = useState<Box | null>(null);

  useLayoutEffect(() => {
    const measure = () => {
      const next = boxOf(findTarget(document, targetKey));
      setBox((prev) => (sameBox(prev, next) ? prev : next));
    };
    measure();
    window.addEventListener("resize", measure);
    window.addEventListener("orientationchange", measure);
    window.addEventListener("scroll", measure, true);
    return () => {
      window.removeEventListener("resize", measure);
      window.removeEventListener("orientationchange", measure);
      window.removeEventListener("scroll", measure, true);
    };
  }, [targetKey]);

  useEffect(() => onBox(box), [box, onBox]);

  return (
    <>
      <div
        className="tour-dim"
        aria-hidden="true"
        style={box ? { clipPath: holePath(box) } : undefined}
      />
      {box && (
        <div
          className="tour-ring"
          aria-hidden="true"
          data-testid="tour-ring"
          style={{
            left: box.left,
            top: box.top,
            width: box.width,
            height: box.height,
          }}
        />
      )}
    </>
  );
}
