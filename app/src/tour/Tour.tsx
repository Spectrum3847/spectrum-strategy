import { type KeyboardEvent, useEffect, useId, useRef, useState } from "react";
import { useLocation, useNavigate } from "react-router";
import { Spotlight } from "./Spotlight";
import type { TourStep } from "./steps";
import { type Box, type NavLayout, placeCard, targetKey } from "./target";
import "./tour.css";

const focusable = "button:not([disabled])";

export function Tour({
  steps,
  layout,
  barPaths,
  onClose,
}: {
  steps: TourStep[];
  layout: NavLayout;
  barPaths: string[];
  onClose(): void;
}) {
  const navigate = useNavigate();
  const here = useLocation();
  const current = `${here.pathname}${here.search}`;
  const start = useRef(current);
  const shown = useRef(current);
  const [box, setBox] = useState<Box | null>(null);
  const [index, setIndex] = useState(0);
  const card = useRef<HTMLDivElement>(null);
  const heading = useRef<HTMLHeadingElement>(null);
  const titleId = useId();
  const bodyId = useId();
  const step = steps[index];
  const last = index === steps.length - 1;

  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    return () => opener?.focus();
  }, []);

  // biome-ignore lint/correctness/useExhaustiveDependencies: a new step moves focus to its title
  useEffect(() => {
    heading.current?.focus();
  }, [index]);

  if (!step) return null;

  const go = (i: number) => {
    setIndex(i);
    const dest = steps[i]?.to ?? start.current;
    if (dest !== shown.current) navigate(dest, { replace: true });
    shown.current = dest;
  };

  const close = () => {
    if (start.current !== shown.current || start.current !== current) {
      navigate(start.current, { replace: true });
    }
    onClose();
  };

  const placement = placeCard(box, layout);

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.key === "Escape") {
      e.stopPropagation();
      close();
      return;
    }
    if (e.key !== "Tab") return;
    const items = [
      ...(card.current?.querySelectorAll<HTMLElement>(focusable) ?? []),
    ];
    const first = items[0];
    const end = items[items.length - 1];
    if (!first || !end) return;
    const active = document.activeElement;
    if (e.shiftKey && (active === first || active === heading.current)) {
      e.preventDefault();
      end.focus();
    } else if (!e.shiftKey && active === end) {
      e.preventDefault();
      first.focus();
    }
  };

  return (
    <div
      className="tour-scrim"
      data-place={placement?.place}
      style={
        placement?.place === "side"
          ? { paddingLeft: placement.clear }
          : undefined
      }
    >
      <Spotlight targetKey={targetKey(step.nav, barPaths)} onBox={setBox} />
      <button
        type="button"
        className="tour-backdrop"
        tabIndex={-1}
        aria-hidden="true"
        onClick={close}
      />
      <div
        ref={card}
        className="tour"
        style={
          placement?.place === "top"
            ? { maxHeight: placement.clear }
            : undefined
        }
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={bodyId}
        onKeyDown={onKeyDown}
      >
        <p className="tour-count secondary">
          Step {index + 1} of {steps.length}
        </p>
        <h2 id={titleId} ref={heading} tabIndex={-1}>
          {step.title}
        </h2>
        <p id={bodyId}>{step.body}</p>
        <div className="tour-actions">
          {!last && (
            <button type="button" className="btn" onClick={close}>
              Skip
            </button>
          )}
          {index > 0 && (
            <button type="button" className="btn" onClick={() => go(index - 1)}>
              Back
            </button>
          )}
          <button
            type="button"
            className="btn primary"
            onClick={last ? close : () => go(index + 1)}
          >
            {last ? "Done" : "Next"}
          </button>
        </div>
      </div>
    </div>
  );
}
