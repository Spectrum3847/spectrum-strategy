import {
  allFields,
  effectiveDefault,
  type ScoutConfig,
  type Values,
} from "../scout/config";

export function startValues(
  config: ScoutConfig,
  saved: Values | null,
  draft: Values | null,
): Values {
  const values: Values = {};
  for (const field of allFields(config)) {
    values[field.code] = effectiveDefault(field);
  }
  return { ...values, ...saved, ...draft };
}
