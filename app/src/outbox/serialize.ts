import { arrayRemove, arrayUnion, Timestamp } from "firebase/firestore";

export type Json =
  | null
  | boolean
  | number
  | string
  | Json[]
  | { [key: string]: Json };

const tsTag = "__ts";
const opTag = "__op";

type ArrayOp = "arrayUnion" | "arrayRemove";

export interface ArrayEdit {
  [key: string]: Json;
  __op: ArrayOp;
  values: Json[];
}

export const unionOf = (values: unknown[]): ArrayEdit => ({
  [opTag]: "arrayUnion",
  values: values.map(encodeData),
});

export const removeOf = (values: unknown[]): ArrayEdit => ({
  [opTag]: "arrayRemove",
  values: values.map(encodeData),
});

export function encodeData(value: unknown): Json {
  if (value instanceof Timestamp) {
    return { [tsTag]: [value.seconds, value.nanoseconds] };
  }
  if (value instanceof Date) {
    return { [tsTag]: [Math.floor(value.getTime() / 1000), 0] };
  }
  if (Array.isArray(value)) return value.map(encodeData);
  if (value && typeof value === "object") {
    const out: { [key: string]: Json } = {};
    for (const [k, v] of Object.entries(value)) {
      if (v !== undefined) out[k] = encodeData(v);
    }
    return out;
  }
  if (value === undefined) return null;
  return value as Json;
}

export function decodeData(value: Json): unknown {
  if (Array.isArray(value)) return value.map(decodeData);
  if (value && typeof value === "object") {
    const op = value[opTag];
    const listed = value.values;
    if (
      Object.keys(value).length === 2 &&
      (op === "arrayUnion" || op === "arrayRemove") &&
      Array.isArray(listed)
    ) {
      const decoded = listed.map(decodeData);
      return op === "arrayUnion"
        ? arrayUnion(...decoded)
        : arrayRemove(...decoded);
    }
    const tagged = value[tsTag];
    if (
      Object.keys(value).length === 1 &&
      Array.isArray(tagged) &&
      typeof tagged[0] === "number" &&
      typeof tagged[1] === "number"
    ) {
      return new Timestamp(tagged[0], tagged[1]);
    }
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value)) out[k] = decodeData(v);
    return out;
  }
  return value;
}
