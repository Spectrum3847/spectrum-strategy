import { tbaKeyCache } from "../scout/local";
import { fetchTbaKey } from "../scout/remote";

export async function teamKey(): Promise<string | null> {
  try {
    const fetched = await fetchTbaKey();
    if (fetched === null || fetched === "") {
      if (fetched === "") tbaKeyCache.clear();
    } else {
      tbaKeyCache.set(fetched);
      return fetched;
    }
  } catch {
  }
  return tbaKeyCache.get();
}
