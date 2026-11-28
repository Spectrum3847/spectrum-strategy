// @vitest-environment jsdom
import { cleanup, render } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

const seen = vi.hoisted(() => ({
  props: [] as Record<string, unknown>[],
}));
vi.mock("../assistant/AiCard", () => ({
  AiCard: (props: Record<string, unknown>) => {
    seen.props.push(props);
    return null;
  },
}));

import type { MatchScorePoint } from "../assistant/scoringTrend";
import type { EventRow, TeamHistory } from "./history";
import { BriefCard, TrendCard } from "./TeamAi";

const event = (key: string): EventRow => ({
  event: key,
  eventName: "",
  year: 2026,
  wins: 0,
  losses: 0,
  ties: 0,
  rank: null,
  numTeams: null,
  totalPoints: null,
  autoPoints: null,
  teleopPoints: null,
  endgamePoints: null,
});
const history = (events: string[]): TeamHistory => ({
  seasons: [],
  events: events.map(event),
  awards: [],
  alliances: [],
});
const series: MatchScorePoint[] = ["qm1", "qm2", "qm3"].map((m) => ({
  key: `2027test_${m}`,
  total: 10,
  auto: 3,
  teleop: 5,
  endgame: 2,
  penalties: 0,
  alliance: "Red",
}));
const last = () => seen.props.at(-1) as Record<string, unknown>;

afterEach(() => {
  cleanup();
  seen.props = [];
});

describe("brief card", () => {
  it("hides below two events and while history loads", () => {
    render(
      <BriefCard
        team={1111}
        history={history(["a"])}
        loading={false}
        lead
        uid="u1"
      />,
    );
    expect(last().cacheKey).toBeNull();
    render(
      <BriefCard
        team={1111}
        history={history(["a", "b"])}
        loading
        lead
        uid="u1"
      />,
    );
    expect(last().cacheKey).toBeNull();
  });

  it("keys on the events covered and passes the role through", () => {
    render(
      <BriefCard
        team={1111}
        history={history(["b", "a"])}
        loading={false}
        lead={false}
        uid="u1"
      />,
    );
    expect(last().cacheKey).toBe("team-brief:1111:a,b");
    expect(last().lead).toBe(false);
    expect(last().request).not.toBeNull();
  });
});

describe("trend card", () => {
  it("has no key without an event or three matches", () => {
    render(
      <TrendCard
        team={1111}
        eventKey=""
        series={series}
        history={history([])}
        loading={false}
        lead
        uid="u1"
      />,
    );
    expect(last().cacheKey).toBeNull();
    render(
      <TrendCard
        team={1111}
        eventKey="2027test"
        series={series.slice(0, 2)}
        history={history([])}
        loading={false}
        lead
        uid="u1"
      />,
    );
    expect(last().cacheKey).toBeNull();
  });

  it("keys on the event and team", () => {
    render(
      <TrendCard
        team={1111}
        eventKey="2027test"
        series={series}
        history={history([])}
        loading={false}
        lead
        uid="u1"
      />,
    );
    expect(last().cacheKey).toBe("scoring-trend:2027test:1111");
  });
});
