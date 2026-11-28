import { useRegisterSW } from "virtual:pwa-register/react";

export function UpdatePrompt() {
  const {
    needRefresh: [needRefresh],
    updateServiceWorker,
  } = useRegisterSW();

  if (!needRefresh) return null;
  return (
    <div className="update" role="status">
      <span>A new version is ready</span>
      <button
        type="button"
        className="btn"
        onClick={() => updateServiceWorker(true)}
      >
        Reload
      </button>
    </div>
  );
}
