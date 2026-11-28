import { Timestamp } from "firebase/firestore";
import type { ScoutConfig, Values } from "../scout/config";
import { fieldValuesFor } from "../scout/entry";
import type { FormKind } from "./kinds";

export interface FormDocInput {
  kind: FormKind;
  id: string;
  team: number;
  eventKey: string;
  config: ScoutConfig;
  values: Values;
  authorUid: string;
  authorDisplayName: string;
  now: Date;
  photoKeys?: string[];
}

export function formEntryDocument(
  input: FormDocInput,
): Record<string, unknown> {
  const doc: Record<string, unknown> = {
    id: input.id,
    teamNumber: input.team,
    eventKey: input.eventKey,
    fieldValues: fieldValuesFor(input.config, input.values),
    authorUid: input.authorUid,
    authorDisplayName: input.authorDisplayName.slice(0, 128),
    updatedAt: input.now.toISOString(),
  };
  if (input.kind === "pit") doc.photoKeys = input.photoKeys ?? [];
  doc.updatedAtTs = Timestamp.fromDate(input.now);
  return doc;
}

export function stampAfter(storedMs: number | undefined, now: Date): Date {
  return storedMs !== undefined && storedMs > now.getTime()
    ? new Date(storedMs)
    : now;
}

export const stampFields = (at: Date) => ({
  updatedAt: at.toISOString(),
  updatedAtTs: Timestamp.fromDate(at),
});

export function pitAnswersMerge(
  config: ScoutConfig,
  values: Values,
  storedMs: number | undefined,
  now: Date,
): Record<string, unknown> {
  return {
    fieldValues: fieldValuesFor(config, values),
    ...stampFields(stampAfter(storedMs, now)),
  };
}
