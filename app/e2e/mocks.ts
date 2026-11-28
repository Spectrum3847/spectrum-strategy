import type { BrowserContext, Route } from "@playwright/test";
import {
  buildMatches,
  eventKey,
  eventName,
  type TestMatch,
  teams,
} from "./event.ts";

const pixel = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "base64",
);

const key = (team: number) => `frc${team}`;

function tbaMatch(m: TestMatch) {
  const alliance = (teamsOf: number[], score: number, fuel: number) => ({
    team_keys: teamsOf.map(key),
    score,
    ...(m.played ? { fuel } : {}),
  });
  const redWins = m.redScore > m.blueScore;
  return {
    key: m.key,
    comp_level: "qm",
    set_number: 1,
    match_number: m.number,
    event_key: eventKey,
    time: m.time,
    predicted_time: m.time,
    winning_alliance: m.played ? (redWins ? "red" : "blue") : "",
    alliances: {
      red: alliance(m.red, m.redScore, m.redFuel),
      blue: alliance(m.blue, m.blueScore, m.blueFuel),
    },
    score_breakdown: m.played
      ? {
          red: { hubScore: { totalCount: m.redFuel }, totalPoints: m.redScore },
          blue: {
            hubScore: { totalCount: m.blueFuel },
            totalPoints: m.blueScore,
          },
        }
      : null,
  };
}

function rankings(matches: TestMatch[]) {
  const table = new Map(
    teams.map((t) => [t.number, { w: 0, l: 0, t: 0, played: 0, points: 0 }]),
  );
  for (const m of matches.filter((x) => x.played)) {
    for (const [side, mine, theirs] of [
      [m.red, m.redScore, m.blueScore],
      [m.blue, m.blueScore, m.redScore],
    ] as const) {
      for (const team of side) {
        const row = table.get(team);
        if (!row) continue;
        row.played += 1;
        row.points += mine;
        if (mine > theirs) row.w += 1;
        else if (mine < theirs) row.l += 1;
        else row.t += 1;
      }
    }
  }
  const ordered = [...table.entries()].sort(
    (a, b) => b[1].w - a[1].w || b[1].points - a[1].points || a[0] - b[0],
  );
  return {
    rankings: ordered.map(([team, r], i) => ({
      rank: i + 1,
      team_key: key(team),
      matches_played: r.played,
      record: { wins: r.w, losses: r.l, ties: r.t },
      sort_orders: [r.w * 2, r.points],
    })),
    sort_order_info: [],
  };
}

function predictions(matches: TestMatch[]) {
  const qual: Record<string, unknown> = {};
  for (const m of matches.filter((x) => !x.played)) {
    qual[m.key] = {
      red: { score: m.redFuel + 20 },
      blue: { score: m.blueFuel + 20 },
      prob: 0.55 + (m.number % 5) / 20,
      winning_alliance: m.number % 2 === 0 ? "red" : "blue",
    };
  }
  return { match_predictions: { qual } };
}

function epa() {
  return teams.map((t, i) => ({
    team: t.number,
    epa: { total_points: { mean: 60 - i * 2.5 } },
  }));
}

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({
    status,
    contentType: "application/json",
    headers: { "access-control-allow-origin": "*" },
    body: JSON.stringify(body),
  });

export interface NetworkLog {
  offline: boolean;
  tba: string[];
  statbotics: string[];
  photoUploads: number;
  photoDownloads: number;
  blocked: string[];
  unexpected: string[];
}

const local = /^(http:\/\/(127\.0\.0\.1|localhost)[:/]|data:|blob:|about:)/;

export async function mockNetwork(
  context: BrowserContext,
): Promise<NetworkLog> {
  const matches = buildMatches();
  const log: NetworkLog = {
    offline: false,
    tba: [],
    statbotics: [],
    photoUploads: 0,
    photoDownloads: 0,
    blocked: [],
    unexpected: [],
  };

  const setOffline = context.setOffline.bind(context);
  context.setOffline = async (offline: boolean) => {
    log.offline = offline;
    await setOffline(offline);
  };
  const answer = (handler: (route: Route) => unknown) => (route: Route) =>
    log.offline ? route.abort("internetdisconnected") : handler(route);

  await context.route(
    (url) => !local.test(url.href),
    (route) => {
      const request = `${route.request().method()} ${route.request().url()}`;
      const url = new URL(route.request().url());
      const google = /(^|\.)(google|gstatic)\.com$/.test(url.hostname);
      (google ? log.blocked : log.unexpected).push(request);
      return route.abort();
    },
  );

  await context.route(
    "https://www.thebluealliance.com/api/v3/**",
    answer((route) => {
      const { pathname } = new URL(route.request().url());
      const path = pathname.replace("/api/v3", "");
      log.tba.push(path);
      if (route.request().method() === "OPTIONS") {
        return route.fulfill({
          status: 204,
          headers: {
            "access-control-allow-origin": "*",
            "access-control-allow-headers": "*",
          },
        });
      }
      if (path.endsWith("/teams/simple")) {
        return json(
          route,
          teams.map((t) => ({
            key: key(t.number),
            team_number: t.number,
            nickname: t.nickname,
            name: t.nickname,
          })),
        );
      }
      if (path.endsWith("/rankings")) return json(route, rankings(matches));
      if (path.endsWith("/predictions"))
        return json(route, predictions(matches));
      if (path.endsWith("/matches/simple") || path.endsWith("/matches")) {
        return json(route, matches.map(tbaMatch));
      }
      if (path.endsWith("/simple")) {
        return json(route, {
          key: eventKey,
          name: eventName,
          event_type: 0,
          event_type_string: "Regional",
          year: 2027,
        });
      }
      log.unexpected.push(`TBA ${path}`);
      return json(route, { Error: "not in the fixtures" }, 404);
    }),
  );

  await context.route(
    "https://api.statbotics.io/v3/**",
    answer((route) => {
      const { pathname, searchParams } = new URL(route.request().url());
      log.statbotics.push(pathname);
      if (searchParams.has("team")) return json(route, []);
      return json(route, epa());
    }),
  );

  await context.route(
    "https://photos.example.test/**",
    answer((route) => {
      const headers = { "access-control-allow-origin": "*" };
      const method = route.request().method();
      if (method === "OPTIONS") {
        return route.fulfill({
          status: 204,
          headers: {
            ...headers,
            "access-control-allow-headers": "*",
            "access-control-allow-methods": "GET, POST, DELETE",
          },
        });
      }
      if (method === "POST") {
        log.photoUploads += 1;
        return json(route, { key: `photo-${log.photoUploads}` }, 201);
      }
      if (method === "DELETE") return route.fulfill({ status: 204, headers });
      log.photoDownloads += 1;
      return route.fulfill({
        status: 200,
        contentType: "image/png",
        headers,
        body: pixel,
      });
    }),
  );

  return log;
}
