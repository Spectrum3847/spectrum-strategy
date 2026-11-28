const refreshers = new Set<() => Promise<void>>();

export function registerRefresh(refresh: () => Promise<void>): () => void {
  refreshers.add(refresh);
  return () => refreshers.delete(refresh);
}

export async function refreshEventData(): Promise<void> {
  await Promise.all([...refreshers].map((refresh) => refresh()));
}
