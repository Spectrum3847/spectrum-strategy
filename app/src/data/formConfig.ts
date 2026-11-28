import bundledPit from "../../../assets/pit_scout_config_default.json";
import bundledPrescout from "../../../assets/prescout_config_default.json";
import { parseConfig, pickConfig, type ScoutConfig } from "../scout/config";

export type FormKind = "pit" | "prescout";

export const bundledConfig: Record<FormKind, ScoutConfig> = {
  pit: parseConfig(bundledPit),
  prescout: parseConfig(bundledPrescout),
};

export const configDocId = {
  pit: "pitScoutConfig",
  prescout: "prescoutConfig",
} as const;

export function resolveConfig(
  bundled: ScoutConfig,
  copies: (string | null)[],
): ScoutConfig {
  let active = bundled;
  for (const json of copies) {
    if (!json) continue;
    try {
      active = pickConfig(active, parseConfig(json));
    } catch {
    }
  }
  return active;
}

export function replacesCached(cached: string | null, incoming: string) {
  let next: ScoutConfig;
  try {
    next = parseConfig(incoming);
  } catch {
    return false;
  }
  if (!cached) return true;
  try {
    return pickConfig(parseConfig(cached), next) === next;
  } catch {
    return true;
  }
}
