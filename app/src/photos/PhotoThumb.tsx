import { useEffect, useRef, useState } from "react";
import { fetchPhoto } from "./service";
import "./photos.css";

export type PhotoSource = { blob: Blob } | { key: string };

type Src =
  | { status: "loading" }
  | { status: "ready"; url: string }
  | { status: "missing"; text: string };

const missingText: Record<string, string> = {
  offline: "Connect to see this photo",
  unconfigured: "Photo storage is not set up",
  "signed-out": "Sign in to see this photo",
  failed: "Could not load this photo",
};

function useSrc(source: PhotoSource, attempt: number): Src {
  const blob = "blob" in source ? source.blob : null;
  const key = "key" in source ? source.key : null;
  const [src, setSrc] = useState<Src>({ status: "loading" });

  // biome-ignore lint/correctness/useExhaustiveDependencies: attempt reruns the fetch
  useEffect(() => {
    if (blob) {
      const url = URL.createObjectURL(blob);
      setSrc({ status: "ready", url });
      return () => URL.revokeObjectURL(url);
    }
    if (key === null) return;
    let live = true;
    setSrc({ status: "loading" });
    fetchPhoto(key).then((result) => {
      if (!live) return;
      setSrc(
        result.type === "ok"
          ? { status: "ready", url: result.url }
          : {
              status: "missing",
              text:
                missingText[
                  result.type === "unavailable" ? result.reason : "failed"
                ] ?? "Could not load this photo",
            },
      );
    });
    return () => {
      live = false;
    };
  }, [blob, key, attempt]);

  return src;
}

export function PhotoThumb({
  source,
  label,
}: {
  source: PhotoSource;
  label: string;
}) {
  const [attempt, setAttempt] = useState(0);
  const [open, setOpen] = useState(false);
  const src = useSrc(source, attempt);

  if (src.status !== "ready") {
    return (
      <div className="photo-thumb photo-empty">
        <p className="photo-empty-text secondary">
          {src.status === "loading" ? "Loading" : src.text}
        </p>
        {src.status === "missing" && (
          <button
            type="button"
            className="btn"
            onClick={() => setAttempt(attempt + 1)}
          >
            Try again
          </button>
        )}
      </div>
    );
  }
  return (
    <>
      <button
        type="button"
        className="photo-thumb"
        aria-label={`View ${label}`}
        onClick={() => setOpen(true)}
      >
        <img src={src.url} alt={label} />
      </button>
      {open && (
        <PhotoViewer
          url={src.url}
          label={label}
          onClose={() => setOpen(false)}
        />
      )}
    </>
  );
}

function PhotoViewer({
  url,
  label,
  onClose,
}: {
  url: string;
  label: string;
  onClose(): void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (typeof dialog.showModal === "function") dialog.showModal();
    else dialog.setAttribute("open", "");
  }, []);
  function close() {
    const dialog = ref.current;
    if (dialog && typeof dialog.close === "function") dialog.close();
    else onClose();
  }
  return (
    <dialog
      ref={ref}
      className="photo-view"
      aria-label={label}
      onClose={onClose}
    >
      <img src={url} alt={label} />
      <button type="button" className="btn" onClick={close}>
        Close
      </button>
    </dialog>
  );
}
