import { fitWithin, jpegQuality, maxEdge, usableOriginal } from "./resize";

async function reencode(file: Blob): Promise<Blob | null> {
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    const { width, height } = fitWithin(
      image.naturalWidth,
      image.naturalHeight,
      maxEdge,
    );
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d");
    if (!context) return null;
    context.drawImage(image, 0, 0, width, height);
    return await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, "image/jpeg", jpegQuality),
    );
  } finally {
    URL.revokeObjectURL(url);
  }
}

export async function preparePhoto(file: File): Promise<Blob> {
  try {
    const blob = await reencode(file);
    if (blob && blob.size > 0) return blob;
  } catch {
  }
  if (usableOriginal(file.type, file.size)) return file;
  throw new Error("This photo could not be read or is too large to upload.");
}
