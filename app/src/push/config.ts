export const vapidPublicKey =
  import.meta.env.VITE_VAPID_PUBLIC_KEY ??
  "BOucdc9DnIIOu7Pwvw7JZzwT645RdQcl06b-a2wOTOZ6rp7m2wgo92BvR_zHoqtoYGYBxWyhqdzpYChfSwQyyso";

export const pushWorkerOrigin = (
  import.meta.env.VITE_PUSH_WORKER_URL ??
  "https://spectrumstrategy-crons.spectrum-3847.workers.dev"
).replace(/\/$/, "");
