export const maxEdge = 1280;
export const jpegQuality = 0.8;
export const maxBytes = 2 * 1024 * 1024;
export const maxPhotos = 3;

const workerTypes = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
]);

export const isWorkerType = (type: string) => workerTypes.has(type);

export function fitWithin(
  width: number,
  height: number,
  edge: number = maxEdge,
): { width: number; height: number } {
  const longest = Math.max(width, height);
  if (longest <= edge) return { width, height };
  const scale = edge / longest;
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
  };
}

export function usableOriginal(type: string, size: number): boolean {
  return isWorkerType(type) && size > 0 && size <= maxBytes;
}
