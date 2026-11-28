import { useEffect, useRef, useState } from "react";
import "./ui.css";

export function DeleteButton({
  what,
  prompt,
  onConfirm,
}: {
  what: string;
  prompt: string;
  onConfirm(): Promise<void>;
}) {
  const [asking, setAsking] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const cancel = useRef<HTMLButtonElement>(null);
  const ask = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (asking) cancel.current?.focus();
  }, [asking]);

  const close = () => {
    setAsking(false);
    ask.current?.focus();
  };

  async function confirmed() {
    setBusy(true);
    try {
      await onConfirm();
      setAsking(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not delete.");
      setAsking(false);
    } finally {
      setBusy(false);
    }
  }

  if (!asking) {
    return (
      <span className="delete-ask">
        <button
          ref={ask}
          type="button"
          className="btn"
          aria-label={`Delete ${what}`}
          onClick={() => {
            setError(null);
            setAsking(true);
          }}
        >
          Delete
        </button>
        {error && (
          <span className="notice" role="alert">
            {error}
          </span>
        )}
      </span>
    );
  }
  return (
    // biome-ignore lint/a11y/useSemanticElements: an inline group, not a fieldset
    <span
      className="delete-ask"
      role="group"
      aria-label={prompt}
      onKeyDown={(e) => {
        if (e.key === "Escape") close();
      }}
    >
      <span className="delete-prompt">{prompt}</span>
      <button ref={cancel} type="button" className="btn" onClick={close}>
        Cancel
      </button>
      <button
        type="button"
        className="btn delete-confirm"
        disabled={busy}
        aria-label={`Confirm delete ${what}`}
        onClick={() => void confirmed()}
      >
        Delete
      </button>
    </span>
  );
}
