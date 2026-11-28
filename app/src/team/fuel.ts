import type { EventEntry } from "../data/parse";
import {
  allFields,
  labelForStored,
  type ScoutConfig,
  type ScoutField,
} from "../scout/config";
import { iqm, mean, numberOf, sd } from "./stats";

const autoFuelCode = "autoFuelScored";
const teleopFuelCode = "teleopFuelScored";

export interface Samples {
  n: number;
  mean: number;
  iqm: number;
  max: number;
  sd: number | null;
}

export interface FuelStats {
  auto: Samples | null;
  teleop: Samples | null;
}

function samples(entries: EventEntry[], code: string): Samples | null {
  const values = entries
    .map((e) => numberOf(e.fieldValues[code]))
    .filter((v): v is number => v !== null);
  if (values.length === 0) return null;
  return {
    n: values.length,
    mean: mean(values),
    iqm: iqm(values),
    max: Math.max(...values),
    sd: values.length < 2 ? null : sd(values),
  };
}

export function fuelStats(entries: EventEntry[]): FuelStats {
  return {
    auto: samples(entries, autoFuelCode),
    teleop: samples(entries, teleopFuelCode),
  };
}

const successLabels = new Set(["Outpost", "Middle", "Depot", "Successful"]);

export const climbField = (
  config: ScoutConfig,
  code: string,
): ScoutField | null => allFields(config).find((f) => f.code === code) ?? null;

export function anyClimb(
  entries: EventEntry[],
  field: ScoutField | null,
): boolean {
  if (!field) return false;
  return entries.some((e) => {
    const raw = e.fieldValues[field.code];
    return (
      raw !== undefined &&
      raw !== null &&
      successLabels.has(labelForStored(field, raw))
    );
  });
}
