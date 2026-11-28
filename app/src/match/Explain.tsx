import { TeamLink } from "../ui/TeamLink";
import type {
  PredictionWhy,
  ResultWhy,
  RobotForecast,
  RobotResult,
  SideResult,
} from "./explain";
import type { Side } from "./robots";

const r0 = Math.round;
const signed = (n: number) => `${n >= 0 ? "+" : "-"}${Math.abs(r0(n))}`;
const sideName: Record<Side, string> = { red: "Red", blue: "Blue" };

function forecastText(r: RobotForecast): string {
  const parts: string[] = [];
  if (r.mean !== null && r.sd !== null) {
    parts.push(
      `Scouting ${r0(r.mean)} fuel a match, varying by about ${r0(r.sd)}, from ${r.entries} scouted matches`,
    );
  } else {
    parts.push(
      r.entries === 0
        ? "Not scouted this event"
        : `Scouting has only ${r.entries} scouted match${r.entries === 1 ? "" : "es"}, too few to forecast`,
    );
  }
  if (r.epa !== null) parts.push(`Statbotics EPA ${r0(r.epa)} points`);
  return parts.join(". ");
}

export function WhyPrediction({
  why,
  before,
}: {
  why: PredictionWhy;
  before: boolean;
}) {
  return (
    <>
      <p className="secondary">
        {before
          ? "Made as it stood before the match, from scouting of earlier matches only. The Blue Alliance forecast is also its pre-match one. Statbotics EPA is the latest figure."
          : "Made from all scouting so far."}
      </p>
      <ul className="plain match-notes">
        {why.lines.map((line) => (
          <li key={line}>{line}</li>
        ))}
      </ul>
      <details className="why-more">
        <summary>How each robot's forecast was worked out</summary>
        <ul className="plain why-robots">
          {why.robots.map((r) => (
            <li key={r.team} data-side={r.side}>
              <TeamLink team={r.team} />
              <span>{forecastText(r)}</span>
            </li>
          ))}
        </ul>
        <p className="secondary">
          Sources: scout entries at this event, Statbotics and The Blue
          Alliance. Fuel is the count scouts recorded, auto plus teleop, not
          official points.
        </p>
      </details>
    </>
  );
}

function Official({ s }: { s: SideResult }) {
  const parts = [
    s.fuel !== null && `fuel ${s.fuel}`,
    s.climb !== null && `climb ${s.climb}`,
    s.fouls !== null && `fouls ${s.fouls}`,
    s.rest !== null && s.rest !== 0 && `other ${s.rest}`,
  ].filter((p): p is string => p !== false);
  const counts =
    s.foulCount !== null
      ? `, ${s.foulCount} foul${s.foulCount === 1 ? "" : "s"}${s.techFoulCount ? ` and ${s.techFoulCount} tech` : ""} drawn`
      : "";
  return (
    <>
      <p>
        Official total {s.score}
        {parts.length > 0 ? ` = ${parts.join(" + ")}` : ""}
        {counts}
      </p>
      {s.forecastScore !== null && (
        <p className="secondary">
          The Blue Alliance forecast {r0(s.forecastScore)}, official {s.score} (
          {signed(s.score - s.forecastScore)})
        </p>
      )}
      {s.split ? (
        <p className="secondary">
          Fuel: official {s.fuel} against forecast{" "}
          {r0((s.fuel ?? 0) - s.split.miss)} ({signed(s.split.miss)}) is robots
          against their forecasts {signed(s.split.robotPart)} plus fuel the
          scouts did not see {signed(s.split.unseen)}
        </p>
      ) : (
        <p className="secondary">
          The fuel miss is not split: it needs every robot scouted in this match
          and in 3 earlier ones, and the official fuel count.
        </p>
      )}
    </>
  );
}

function Robot({ r }: { r: RobotResult }) {
  return (
    <li>
      <TeamLink team={r.team} />
      <span>
        {r.scouted === null
          ? `Not scouted in this match${r.forecast !== null ? `, forecast ${r0(r.forecast)}` : ""}`
          : `Scouted ${r0(r.scouted)} fuel${r.forecast !== null ? ` against forecast ${r0(r.forecast)} (${signed(r.delta ?? 0)})` : ", no forecast"}`}
      </span>
      {r.notes.length > 0 && (
        <span className="secondary">Scouts marked: {r.notes.join(", ")}</span>
      )}
      {r.comment && (
        <span className="secondary">
          {r.comment.scout !== "" ? `${r.comment.scout}: ` : ""}
          {r.comment.text}
        </span>
      )}
    </li>
  );
}

export function WhyResult({
  why,
  breakdownLoaded,
}: {
  why: ResultWhy;
  breakdownLoaded: boolean;
}) {
  return (
    <>
      <p className="match-winner">{why.headline}</p>
      {why.causes.length > 0 ? (
        <ul className="plain match-notes">
          {why.causes.map((c) => (
            <li key={c}>{c}</li>
          ))}
        </ul>
      ) : (
        <p className="secondary">
          No robot or count stands out from the forecast.
        </p>
      )}
      {!breakdownLoaded && (
        <p className="notice-soft" role="status">
          The official score breakdown has not loaded, so fuel, climb and fouls
          are not shown.
        </p>
      )}
      <div className="why-sides">
        {(["red", "blue"] as const).map((side) => (
          <div className="why-side" data-side={side} key={side}>
            <h3>{sideName[side]}</h3>
            <Official s={why.sides[side]} />
            {why.sides[side].defenders.length > 0 && (
              <p className="secondary">
                Defended by {why.sides[side].defenders.join(", ")} (opposing
                scouts)
              </p>
            )}
            <ul className="plain why-robots">
              {why.sides[side].robots.map((r) => (
                <Robot r={r} key={r.team} />
              ))}
            </ul>
          </div>
        ))}
      </div>
      {why.trex.length > 0 && (
        <>
          <h3>T-REx notes from this match</h3>
          <ul className="plain match-comments">
            {why.trex.map((t) => (
              <li key={`${t.team}-${t.trait}-${t.text}`}>
                <p className="match-comment-team">
                  <TeamLink team={t.team} />
                  <span className="secondary">
                    {t.trait}
                    {t.rating !== null ? ` ${t.rating}/5` : ""}
                  </span>
                </p>
                <p>{t.text}</p>
                {t.scout !== "" && <p className="secondary">{t.scout}</p>}
              </li>
            ))}
          </ul>
        </>
      )}
      {why.video !== null && (
        <a
          className="btn why-video"
          href={`https://www.youtube.com/watch?v=${encodeURIComponent(why.video)}`}
          target="_blank"
          rel="noopener noreferrer"
        >
          Watch the match video
        </a>
      )}
    </>
  );
}
