export const eventKey = "2027test";
export const eventName = "Test Regional";
export const ourTeam = 1111;
export const stations = ["R1", "R2", "R3", "B1", "B2", "B3"] as const;

export const teams = [
  { number: 1111, nickname: "Team One" },
  { number: 2222, nickname: "Team Two" },
  { number: 3333, nickname: "Team Three" },
  { number: 4444, nickname: "Team Four" },
  { number: 5555, nickname: "Team Five" },
  { number: 6666, nickname: "Team Six" },
  { number: 7777, nickname: "Team Seven" },
  { number: 8888, nickname: "Team Eight" },
  { number: 9999, nickname: "Team Nine" },
  { number: 1010, nickname: "Team Ten" },
  { number: 2020, nickname: "Team Eleven" },
  { number: 3030, nickname: "Team Twelve" },
];

export const matchCount = 18;
export const playedCount = 8;
const spacingSeconds = 420;

export interface TestMatch {
  key: string;
  number: number;
  red: number[];
  blue: number[];
  played: boolean;
  redScore: number;
  blueScore: number;
  redFuel: number;
  blueFuel: number;
  time: number;
}

export function buildMatches(nowMs: number = Date.now()): TestMatch[] {
  const out: TestMatch[] = [];
  for (let n = 1; n <= matchCount; n++) {
    const start = (3 * (n - 1)) % teams.length;
    const pick = (offset: number) =>
      [0, 1, 2].map(
        (k) => teams[(start + offset + k) % teams.length]?.number ?? 0,
      );
    const played = n <= playedCount;
    const redFuel = 28 + ((n * 7) % 13);
    const blueFuel = 26 + ((n * 5) % 11);
    out.push({
      key: `${eventKey}_qm${n}`,
      number: n,
      red: pick(0),
      blue: pick(3),
      played,
      redScore: played ? redFuel + 20 + (n % 4) * 3 : -1,
      blueScore: played ? blueFuel + 20 + ((n + 1) % 4) * 3 : -1,
      redFuel,
      blueFuel,
      time: Math.floor(nowMs / 1000) + (n - playedCount - 1) * spacingSeconds,
    });
  }
  return out;
}

export const matchRows = (m: TestMatch) => [
  ...m.red.map((team, i) => ({ team, station: stations[i] ?? "R1" })),
  ...m.blue.map((team, i) => ({ team, station: stations[3 + i] ?? "B1" })),
];
