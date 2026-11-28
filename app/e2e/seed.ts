import { readFileSync } from "node:fs";
import accounts from "./accounts.json" with { type: "json" };
import {
  buildMatches,
  eventKey,
  eventName,
  matchRows,
  playedCount,
  stations,
  teams,
} from "./event.ts";

const project = "demo-spectrum-e2e";
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!firestoreHost || !authHost) {
  throw new Error("Run through `firebase emulators:exec` (see app/README.md).");
}
const headers = {
  "Content-Type": "application/json",
  Authorization: "Bearer owner",
};

type Value =
  | string
  | number
  | boolean
  | null
  | Date
  | Value[]
  | { [k: string]: Value };

function encode(v: Value): Record<string, unknown> {
  if (v === null) return { nullValue: null };
  if (typeof v === "string") return { stringValue: v };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") {
    return Number.isInteger(v)
      ? { integerValue: String(v) }
      : { doubleValue: v };
  }
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encode) } };
  return {
    mapValue: {
      fields: Object.fromEntries(
        Object.entries(v).map(([k, x]) => [k, encode(x)]),
      ),
    },
  };
}

async function check(response: Response, what: string) {
  if (!response.ok) {
    throw new Error(`${what}: ${response.status} ${await response.text()}`);
  }
}

async function put(path: string, data: { [k: string]: Value }) {
  const body = {
    fields: Object.fromEntries(
      Object.entries(data).map(([k, v]) => [k, encode(v)]),
    ),
  };
  const url = `http://${firestoreHost}/v1/projects/${project}/databases/(default)/documents/${path}`;
  await check(
    await fetch(url, { method: "PATCH", headers, body: JSON.stringify(body) }),
    `write ${path}`,
  );
}

async function reset() {
  await check(
    await fetch(
      `http://${firestoreHost}/emulator/v1/projects/${project}/databases/(default)/documents`,
      { method: "DELETE", headers },
    ),
    "clear Firestore",
  );
  await check(
    await fetch(`http://${authHost}/emulator/v1/projects/${project}/accounts`, {
      method: "DELETE",
      headers,
    }),
    "clear Auth",
  );
}

const now = new Date();
const iso = now.toISOString();
const matches = buildMatches(now.getTime());
const scouters = accounts.filter((a) => a.roles.includes("scouter"));
const lead = accounts.find((a) => a.uid === "lead-b");
if (!lead) throw new Error("accounts.json needs lead-b");

async function seedAccounts() {
  for (const a of accounts) {
    await check(
      await fetch(
        `http://${authHost}/identitytoolkit.googleapis.com/v1/projects/${project}/accounts`,
        {
          method: "POST",
          headers,
          body: JSON.stringify({
            localId: a.uid,
            email: a.email,
            displayName: a.name,
            emailVerified: true,
          }),
        },
      ),
      `create ${a.uid}`,
    );
    await put(`userProfiles/${a.uid}`, {
      uid: a.uid,
      displayName: a.name,
      email: a.email,
      roles: a.roles,
      createdAt: iso,
    });
  }
}

async function seedConfig() {
  await put("appConfig/activeEvent", { eventKey });
  await put("appConfig/scoutConfig", {
    configJson: readFileSync(
      new URL("../../assets/scout_config_default.json", import.meta.url),
      "utf8",
    ),
  });
  await put("appConfig/apiKeys", {
    tba: "fake-tba-key-0000",
    photoWorker: "https://photos.example.test",
  });
}

async function seedShifts() {
  const blockLength = 3;
  const blocks = Math.ceil(matches.length / blockLength);
  const rotations = scouters.map((scout, col) => ({
    uid: scout.uid,
    name: scout.name,
    shifts: Array.from({ length: blocks }, (_, b) => b).flatMap((b) => {
      const s = (col - b + scouters.length * blocks) % scouters.length;
      const station = stations[s];
      return station === undefined
        ? []
        : [
            {
              startMatch: b * blockLength + 1,
              endMatch: Math.min(matches.length, (b + 1) * blockLength),
              station,
            },
          ];
    }),
  }));
  await put(`scoutShifts/${eventKey}`, {
    id: eventKey,
    eventKey,
    matchCount: matches.length,
    roster: scouters.map((s) => ({ uid: s.uid, name: s.name })),
    rotations,
    cellOverrides: [],
    authorUid: lead?.uid ?? "",
    authorDisplayName: lead?.name ?? "",
    updatedAt: iso,
    updatedAtTs: now,
  });
}

const starts = ["Depot Trench", "Outpost Trench", "Center Hub", "Depot Bump"];
const climbs = ["N/A", "Failed", "Successful"];

async function seedScoutEntries() {
  for (const m of matches.filter((x) => x.played)) {
    for (const [i, row] of matchRows(m).entries()) {
      const block = Math.floor((m.number - 1) / 3);
      const s = stations.indexOf(row.station as (typeof stations)[number]);
      const scout = scouters[(s + block) % scouters.length] ?? scouters[0];
      if (!scout) continue;
      const share = (row.station.startsWith("R") ? m.redFuel : m.blueFuel) / 3;
      const auto = Math.round(share * 0.3) + (i % 3);
      const teleop = Math.round(share * 0.7) - (i % 2);
      const id = `entry-qm${m.number}-${row.team}`;
      await put(`scoutEntries/${id}`, {
        id,
        matchId: m.key,
        teamNumber: row.team,
        alliance: row.station.startsWith("R") ? "Red" : "Blue",
        notes: "",
        authorUid: scout.uid,
        authorDisplayName: scout.name,
        scoutedByName: scout.name,
        scoutedByUid: scout.uid,
        updatedAt: iso,
        createdAt: iso,
        byPhase: Object.fromEntries(
          ["auton", "teleop", "endgame"].map((p) => [
            p,
            { score: 0, penalties: 0, notes: "", counters: {} },
          ]),
        ),
        fieldValues: {
          scouter: scout.name.replace(" ", ""),
          matchNumber: String(m.number),
          robot: row.station,
          pTnumber: String(row.team),
          starting: starts[(m.number + i) % starts.length] ?? "Center Hub",
          autoFuelScored: auto,
          auLow: "N/A",
          teleopFuelScored: teleop,
          scoringEff: 50 + ((m.number * 5 + i * 10) % 50),
          tRdefense: i % 5 === 0,
          tRpasser: i % 4 === 0,
          ePclimb: "N/A",
          eLow: climbs[(m.number + i) % climbs.length] ?? "N/A",
          eMiddle: "N/A",
          eHigh: "N/A",
          ryCard: "None",
          dieCard: false,
          comments: i === 1 ? "Fast cycles, drops fuel on the bump." : "",
        },
        tbaMatchKey: m.key,
        updatedAtTs: now,
      });
    }
  }
}

async function seedForms() {
  const author = {
    authorUid: "scout-a",
    authorDisplayName: "Scout A",
    updatedAt: iso,
    updatedAtTs: now,
  };
  for (const t of teams.slice(0, 4)) {
    const id = `pit-${t.number}`;
    await put(`pitScoutEntries/${id}`, {
      id,
      teamNumber: t.number,
      eventKey,
      fieldValues: {
        drivetrainType: "swerve",
        swerveModuleType: "Generic module",
        maxFuelCapacity: "40",
        climbLevel: ["low", "middle"],
        trenchFit: true,
        shootsWhileMoving: t.number % 2 === 0,
        comments: "Pit answers for a test team.",
      },
      photoKeys: [],
      ...author,
    });
  }
  for (const t of teams.slice(0, 2)) {
    const id = `prescout-${t.number}`;
    await put(`prescoutEntries/${id}`, {
      id,
      teamNumber: t.number,
      eventKey,
      fieldValues: {
        watchedEvent: "2026test",
        matchType: "qual",
        matchNumber: "12",
        startingPosition: "centerHub",
        autoFuelScored: 6,
        autoClimbL1: "na",
        teleopFuelScored: 18,
        endgameClimb: "l2",
      },
      ...author,
    });
  }
  const reports: [string, number, number, string][] = [
    ["autonomous", 2222, 5, "Reliable two piece auto."],
    ["defense", 3333, 3, "Plays defense late, a few pins."],
    ["driverSkill", 4444, 4, "Calm under pressure."],
    ["defense", 2222, 2, "Slow to react."],
  ];
  for (const [i, [trait, team, rating, report]] of reports.entries()) {
    const id = `trex-${i + 1}`;
    await put(`trexTraitReports/${id}`, {
      id,
      trait,
      teamNumber: team,
      matchNumber: i + 2,
      eventName,
      eventKey,
      report,
      rating,
      ...author,
    });
  }
}

async function seedStrategy() {
  await put(`teamNotes/${eventKey}_2222`, {
    id: `${eventKey}_2222`,
    eventKey,
    teamNumber: 2222,
    text: "Strong shooter, weak defense. Ally with a defender.",
    authorUid: "lead-b",
    authorDisplayName: "Lead B",
    updatedAt: iso,
    updatedAtTs: now,
  });
  await put("pickLists/list-main", {
    id: "list-main",
    name: "Main list",
    teamNumbers: [2222, 3333, 4444, 5555, 6666, 7777],
    tiers: [
      { name: "1st pick", teams: [2222, 3333] },
      { name: "2nd pick", teams: [4444, 5555] },
      { name: "Defense/role", teams: [6666] },
      { name: "Backup", teams: [7777] },
    ],
    dnp: [{ team: 9999, reason: "Broke down in two matches" }],
    updatedAt: iso,
    authorUid: "lead-b",
    authorDisplayName: "Lead B",
    updatedAtTs: now,
  });
  const next = matches[playedCount];
  if (next) {
    const id = `${eventKey}_qm${next.number}`;
    await put(`matchBriefs/${id}`, {
      id,
      eventKey,
      matchId: `qm${next.number}`,
      robotPlans: { [String(next.red[0])]: "Score from the center hub." },
      keyPoints: "Block the bump early.",
      ready: false,
      authorUid: "lead-b",
      authorDisplayName: "Lead B",
      updatedAt: iso,
      updatedAtTs: now,
    });
  }
}

await reset();
await seedAccounts();
await seedConfig();
await seedShifts();
await seedScoutEntries();
await seedForms();
await seedStrategy();
console.log(
  `Seeded ${project}: ${accounts.length} accounts, event ${eventKey}.`,
);
