import type { Outcome } from "../photos/state";
import { maxScreenshots } from "./bugReport";

export interface ScreenshotDeps {
  prepare(file: File): Promise<Blob>;
  upload(blob: Blob): Promise<Outcome>;
}

export async function uploadScreenshots(
  files: readonly File[],
  deps: ScreenshotDeps,
): Promise<{ keys: string[]; dropped: number }> {
  const taken = files.slice(0, maxScreenshots);
  const keys: string[] = [];
  for (const file of taken) {
    try {
      const outcome = await deps.upload(await deps.prepare(file));
      if (
        outcome.type === "response" &&
        outcome.status === 201 &&
        outcome.key
      ) {
        keys.push(outcome.key);
      }
    } catch {
    }
  }
  return { keys, dropped: taken.length - keys.length };
}
