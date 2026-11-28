import { Timestamp } from "firebase/firestore";
import { traits } from "./traits";

export const limits = {
  team: 99999,
  match: 9999,
  eventName: 128,
  eventKey: 64,
  report: 4096,
  author: 128,
  ratingMin: 1,
  ratingMax: 5,
};

export interface ReportInput {
  id: string;
  trait: string;
  team: number;
  match: number;
  eventName: string;
  eventKey: string;
  report: string;
  rating: number;
  strokes?: unknown[];
  authorUid: string;
  authorDisplayName: string;
  now: Date;
}

export function reportDocument(input: ReportInput): Record<string, unknown> {
  return {
    id: input.id,
    trait: input.trait,
    teamNumber: input.team,
    matchNumber: input.match,
    eventName: input.eventName.trim(),
    eventKey: input.eventKey,
    report: input.report.trim(),
    rating: input.rating,
    ...(input.strokes && input.strokes.length > 0
      ? { strokes: input.strokes }
      : {}),
    authorUid: input.authorUid,
    authorDisplayName: input.authorDisplayName.slice(0, limits.author),
    updatedAt: input.now.toISOString(),
    updatedAtTs: Timestamp.fromDate(input.now),
  };
}

export interface Draft {
  trait: string;
  team: string;
  match: string;
  eventName: string;
  rating: number | null;
  report: string;
}

export function problemWith(draft: Draft): string | null {
  if (!traits.some((t) => t.key === draft.trait)) return "Pick a trait.";
  const team = Number(draft.team);
  if (!Number.isInteger(team) || team < 1 || team > limits.team) {
    return "Enter a team number.";
  }
  const match = Number(draft.match);
  if (
    draft.match.trim() === "" ||
    !Number.isInteger(match) ||
    match < 0 ||
    match > limits.match
  ) {
    return "Enter a match number.";
  }
  const event = draft.eventName.trim();
  if (event === "") return "Enter an event.";
  if (event.length > limits.eventName) return "The event name is too long.";
  if (
    draft.rating === null ||
    !Number.isInteger(draft.rating) ||
    draft.rating < limits.ratingMin ||
    draft.rating > limits.ratingMax
  ) {
    return "Pick a rating from 1 to 5.";
  }
  const report = draft.report.trim();
  if (report === "") return "Enter a report.";
  if (report.length > limits.report) {
    return `The report is ${report.length - limits.report} characters too long.`;
  }
  return null;
}
