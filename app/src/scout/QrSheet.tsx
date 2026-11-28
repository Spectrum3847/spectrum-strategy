import { type ReactNode, useEffect, useMemo, useRef } from "react";
import type { SavedEntry } from "./local";
import { qrMatrix, qrMaxBytes, qrPath } from "./qrImage";

const quiet = 4;

export function QrCode({ payload, label }: { payload: string; label: string }) {
  const qr = useMemo(() => qrMatrix(payload), [payload]);
  if (!qr.ok) {
    return (
      <p className="notice" role="alert">
        This entry is {qr.bytes} bytes, more than one QR code can hold (
        {qrMaxBytes} bytes). It cannot be shown as a code. It is still sent to
        the database when the device is online.
      </p>
    );
  }
  const side = qr.size + quiet * 2;
  return (
    <svg
      className="qr-code"
      viewBox={`0 0 ${side} ${side}`}
      shapeRendering="crispEdges"
      role="img"
      aria-label={label}
    >
      <rect className="qr-bg" width={side} height={side} />
      <path className="qr-fg" d={qrPath(qr.modules, quiet)} />
    </svg>
  );
}

export function QrSheet({
  entry,
  delivery,
  onClose,
}: {
  entry: SavedEntry;
  delivery: ReactNode;
  onClose(): void;
}) {
  const close = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    close.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const caption = `Match ${entry.matchNumber}, ${entry.station || "no station"}, team ${entry.team}`;
  return (
    <div
      className="qr-sheet"
      role="dialog"
      aria-modal="true"
      aria-label="QR code"
    >
      <div className="qr-inner">
        {entry.qr === undefined ? (
          <p className="notice" role="alert">
            The QR for this entry is no longer kept on this device. Only the
            newest entries keep one.
          </p>
        ) : (
          <QrCode payload={entry.qr} label={`QR code for ${caption}`} />
        )}
        <div className="qr-caption">
          <p className="qr-title">
            Match {entry.matchNumber}
            <span className="qr-sep">{entry.station || "?"}</span>
            Team {entry.team}
          </p>
          <p>{delivery}</p>
          <p className="secondary">
            Hold the screen steady in front of the other camera. Turn the
            brightness up if it will not scan.
          </p>
        </div>
      </div>
      <div className="qr-foot">
        <button
          ref={close}
          type="button"
          className="btn primary big"
          onClick={onClose}
        >
          Close
        </button>
      </div>
    </div>
  );
}
