/// <reference types="vite/client" />

declare const __APP_VERSION__: string;
declare const __BUILD_SHA__: string;
declare const __BUILD_TIME__: string;

interface ImportMetaEnv {
  readonly VITE_SPECTRUM_APP_KEY?: string;
  readonly VITE_OUTBOX_PROOF?: string;
  readonly VITE_VAPID_PUBLIC_KEY?: string;
  readonly VITE_PUSH_WORKER_URL?: string;
  readonly VITE_FIREBASE_EMULATORS?: string;
}
