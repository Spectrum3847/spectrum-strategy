export function emulatorFlag(
  mode: string,
  value: string | undefined,
): "true" | "false" {
  return value === "true" && mode !== "production" ? "true" : "false";
}
