import { matchLabel, matchOrder, parseMatchKey } from "../data/matchKey";
import type { EventEntry } from "../data/parse";

const cardCode = "ryCard";
const diedCode = "dieCard";

export interface Incidents {
  red: string[];
  yellow: string[];
  unknown: string[];
  died: string[];
}

type Card = "yellow" | "unknown" | "red";
const severity: Record<Card, number> = { yellow: 0, unknown: 1, red: 2 };

function cardOf(raw: unknown): Card | null {
  if (raw === true) return "unknown";
  switch (String(raw)) {
    case "Yellow":
      return "yellow";
    case "Red":
      return "red";
    case "true":
      return "unknown";
    default:
      return null;
  }
}

const diedOf = (raw: unknown) => raw === true || raw === "true";

const cardText: Record<Card, string> = {
  red: "red card",
  yellow: "yellow card",
  unknown: "card",
};

export function entryIncidents(values: Record<string, unknown>): string {
  const card = cardOf(values[cardCode]);
  const text = [
    card ? cardText[card] : "",
    diedOf(values[diedCode]) ? "died" : "",
  ]
    .filter((p) => p !== "")
    .join(", ");
  return text === "" ? text : text[0]?.toUpperCase() + text.slice(1);
}

interface Where {
  id: string;
  order: number;
  label: string;
}

function whereOf(entry: EventEntry): Where {
  const ref = entry.tbaMatchKey ? parseMatchKey(entry.tbaMatchKey) : null;
  if (ref) {
    const key = entry.tbaMatchKey ?? "";
    return {
      id: `${ref.level}${ref.set}m${ref.number}`,
      order: matchOrder(key),
      label: matchLabel(key),
    };
  }
  const typed = Number.parseInt(
    String(entry.fieldValues.matchNumber ?? ""),
    10,
  );
  if (Number.isInteger(typed) && typed > 0) {
    const key = `e_qm${typed}`;
    return {
      id: `qm1m${typed}`,
      order: matchOrder(key),
      label: matchLabel(key),
    };
  }
  return {
    id: `entry ${entry.id}`,
    order: Number.MAX_SAFE_INTEGER,
    label: "(no match number)",
  };
}

export function incidentsByTeam(entries: EventEntry[]): Map<number, Incidents> {
  const cards = new Map<number, Map<string, { card: Card; at: Where }>>();
  const deaths = new Map<number, Map<string, Where>>();
  for (const entry of entries) {
    const at = whereOf(entry);
    const card = cardOf(entry.fieldValues[cardCode]);
    if (card) {
      const byMatch =
        cards.get(entry.teamNumber) ??
        new Map<string, { card: Card; at: Where }>();
      const seen = byMatch.get(at.id);
      if (!seen || severity[card] > severity[seen.card]) {
        byMatch.set(at.id, { card, at });
      }
      cards.set(entry.teamNumber, byMatch);
    }
    if (diedOf(entry.fieldValues[diedCode])) {
      const byMatch = deaths.get(entry.teamNumber) ?? new Map<string, Where>();
      byMatch.set(at.id, at);
      deaths.set(entry.teamNumber, byMatch);
    }
  }
  const labels = (found: Where[]) =>
    [...found].sort((a, b) => a.order - b.order).map((w) => w.label);
  const out = new Map<number, Incidents>();
  for (const team of new Set([...cards.keys(), ...deaths.keys()])) {
    const byMatch = [...(cards.get(team)?.values() ?? [])];
    const withCard = (c: Card) =>
      labels(byMatch.filter((m) => m.card === c).map((m) => m.at));
    out.set(team, {
      red: withCard("red"),
      yellow: withCard("yellow"),
      unknown: withCard("unknown"),
      died: labels([...(deaths.get(team)?.values() ?? [])]),
    });
  }
  return out;
}

export const weight = (i: Incidents) =>
  i.red.length * 3 + i.yellow.length + i.unknown.length + i.died.length;

export const suggestsDoNotPick = (i: Incidents) => weight(i) >= 2;

export function describe(i: Incidents): string {
  const parts = [
    i.red.length > 0 ? `red card ${i.red.join(", ")}` : "",
    i.yellow.length > 0 ? `yellow card ${i.yellow.join(", ")}` : "",
    i.unknown.length > 0 ? `card ${i.unknown.join(", ")}` : "",
    i.died.length > 0 ? `died ${i.died.join(", ")}` : "",
  ].filter((p) => p !== "");
  const text = parts.join(" · ");
  return text === "" ? text : text[0]?.toUpperCase() + text.slice(1);
}

export interface Suggestion {
  team: number;
  reason: string;
}

export function suggestions(
  byTeam: Map<number, Incidents>,
  except: Set<number>,
  us: number | null,
): Suggestion[] {
  return [...byTeam.entries()]
    .filter(
      ([team, i]) => suggestsDoNotPick(i) && !except.has(team) && team !== us,
    )
    .sort(([ta, a], [tb, b]) => weight(b) - weight(a) || ta - tb)
    .map(([team, i]) => ({ team, reason: describe(i) }));
}
