export interface Field {
  id: string;
  game: string;
  image: string;
  aspect: number;
}

export interface Fields {
  fields: Field[];
  latest: string;
}

type Raw = Record<string, unknown>;
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const baseName = (path: string) => path.slice(path.lastIndexOf("/") + 1);

function byName<T>(files: Record<string, T>): Map<string, T> {
  return new Map(Object.entries(files).map(([p, v]) => [baseName(p), v]));
}

export function loadFields(
  jsonFiles: Record<string, unknown>,
  imageFiles: Record<string, string>,
): Fields {
  const jsons = byName(jsonFiles);
  const images = byName(imageFiles);
  const manifest = jsons.get("MANIFEST.json");
  const listed =
    isRecord(manifest) && Array.isArray(manifest.fields) ? manifest.fields : [];
  const fields: Field[] = [];
  for (const entry of listed) {
    if (!isRecord(entry) || typeof entry.id !== "string") continue;
    const json = jsons.get(baseName(String(entry.json ?? "")));
    if (!isRecord(json)) continue;
    const image = images.get(String(json["field-image"] ?? ""));
    const game = typeof json.game === "string" ? json.game.trim() : "";
    if (image === undefined || game === "") continue;
    const size = Array.isArray(json["field-size"]) ? json["field-size"] : [];
    const [w, h] = size;
    fields.push({
      id: entry.id,
      game,
      image,
      aspect:
        typeof w === "number" && typeof h === "number" && h > 0 ? w / h : 2,
    });
  }
  fields.sort((a, b) => a.id.localeCompare(b.id));
  const named =
    isRecord(manifest) && typeof manifest.latest === "string"
      ? manifest.latest
      : "";
  return { fields, latest: named !== "" ? named : (fields.at(-1)?.id ?? "") };
}

export const bundled = loadFields(
  import.meta.glob("../../../assets/fields/wpilib/*.json", {
    eager: true,
    import: "default",
  }),
  import.meta.glob("../../../assets/fields/wpilib/*.{png,jpg,jpeg,webp}", {
    eager: true,
    query: "?url",
    import: "default",
  }),
);

export function fieldFor(fields: Fields, id: string): Field | null {
  return (
    fields.fields.find((f) => f.id === id) ??
    fields.fields.find((f) => f.id === fields.latest) ??
    null
  );
}
