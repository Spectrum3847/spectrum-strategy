import { useEffect, useMemo, useState } from "react";
import { TeamLink } from "../ui/TeamLink";
import type { Robot } from "./data";
import { matches, model, seeded } from "./model";
import "./bracket.css";

const tops = [
  80, 200, 320, 440, 570, 690, 130, 370, 570, 690, 250, 630, 630, 440,
];

export function Bracket({
  alliances,
  robots,
}: {
  alliances: number[][];
  robots: Map<number, Robot>;
}) {
  const [through, setThrough] = useState(0),
    [playing, setPlaying] = useState(false),
    [random, setRandom] = useState(false),
    [seed, setSeed] = useState(1);
  const valid = alliances.length === 8 && alliances.every((a) => a.length >= 3);
  const playoff = useMemo(
    () => (valid ? model(alliances, robots) : null),
    [alliances, robots, valid],
  );
  const odds = useMemo(() => playoff?.odds(), [playoff]);
  const likely = useMemo(() => playoff?.run().champion ?? 0, [playoff]);
  useEffect(() => {
    if (!playing) return;
    const timer = window.setInterval(
      () =>
        setThrough((n) => {
          if (n >= 13) {
            setPlaying(false);
            return 14;
          }
          return n + 1;
        }),
      750,
    );
    return () => window.clearInterval(timer);
  }, [playing]);
  if (!playoff || !odds)
    return (
      <section>
        <h2>Playoff bracket</h2>
        <p>
          Complete all eight alliances with at least three teams to see the
          bracket.
        </p>
      </section>
    );
  const result = playoff.run(through, random ? seeded(seed) : undefined);
  const favorite = odds.title.indexOf(Math.max(...odds.title)) + 1;
  const label = ([kind, n]: (typeof matches)[number]["a"]) =>
    kind === "seed"
      ? `Alliance ${n}`
      : `${kind === "winner" ? "Winner" : "Loser"} of M${n}`;
  return (
    <section className="bracket-section">
      <h2>Playoff bracket</h2>
      <p className="secondary">
        Expected scores use the average of every scouted match. Teams without
        scouting contribute zero; their uncertainty is estimated.
      </p>
      <div className="actions">
        <label>
          Simulate through{" "}
          <input
            aria-label="Simulate through"
            type="range"
            min="0"
            max="14"
            value={through}
            onPointerDown={() => setPlaying(false)}
            onChange={(e) => {
              setPlaying(false);
              setThrough(Number(e.target.value));
            }}
          />
        </label>
        <strong>
          {through === 0
            ? "Before playoffs"
            : through === 14
              ? "Finals"
              : `Match ${through}`}
        </strong>
        <button
          className="btn"
          type="button"
          onClick={() => {
            if (!playing && through === 14) setThrough(0);
            setPlaying(!playing);
          }}
        >
          {playing ? "Pause" : "Play"}
        </button>
        <button
          className="btn"
          type="button"
          onClick={() => {
            setPlaying(false);
            setRandom(!random);
          }}
        >
          {random ? "Most likely path" : "Random path"}
        </button>
        {random && (
          <button
            className="btn"
            type="button"
            onClick={() => {
              setPlaying(false);
              setSeed(seed + 1);
            }}
          >
            Run again
          </button>
        )}
      </div>
      <section className="bracket-scroll" aria-label="Playoff bracket">
        <div className="bracket-grid">
          {[
            "Round 1",
            "Round 2",
            "Round 3",
            "Round 4",
            "Round 5",
            "Finals",
          ].map((name, i) => (
            <h3
              key={name}
              className="bracket-heading"
              style={{ left: i * 270 }}
            >
              {name}
            </h3>
          ))}
          <svg
            className="bracket-lines"
            width="1580"
            height="820"
            aria-hidden="true"
          >
            {matches.flatMap((m, i) =>
              [m.a, m.b].map(([kind, number], side) => {
                if (kind === "seed") return null;
                const source = matches[number - 1];
                if (!source) return null;
                const x1 = source.round * 270 + 230,
                  y1 = (tops[number - 1] ?? 0) + 50,
                  x2 = m.round * 270,
                  y2 = (tops[i] ?? 0) + 38 + side * 32;
                return (
                  <path
                    key={`${m.a.join("-")}-${m.b.join("-")}-${kind}-${number}`}
                    d={`M${x1} ${y1} H${x2 - 12} V${y2} H${x2}`}
                    className={kind === "loser" ? "bracket-drop" : ""}
                  />
                );
              }),
            )}
          </svg>
          {result.played.map((m, i) => (
            <div
              className="bracket-match"
              key={`${m.a.join("-")}-${m.b.join("-")}`}
              style={{ left: m.round * 270, top: tops[i] }}
            >
              <strong>{i === 13 ? "Finals" : `Match ${i + 1}`}</strong>
              {(
                [
                  [m.aSeed, m.a],
                  [m.bSeed, m.b],
                ] as const
              ).map(([alliance, slot], side) => (
                <div
                  key={slot.join("-")}
                  className={
                    m.winner === alliance && alliance ? "bracket-winner" : ""
                  }
                >
                  {alliance ? (
                    <>
                      Alliance {alliance}:{" "}
                      {alliances[alliance - 1]?.map((team, j) => (
                        <span key={team}>
                          {j > 0 && " · "}
                          <TeamLink team={team} />
                        </span>
                      ))}
                    </>
                  ) : (
                    label(slot)
                  )}{" "}
                  {alliance && m.chance !== null
                    ? `(${Math.round((side === 0 ? m.chance : 1 - m.chance) * 100)}%)`
                    : ""}
                </div>
              ))}
            </div>
          ))}
        </div>
      </section>
      {result.champion > 0 && (
        <p>Predicted champion: Alliance {result.champion}</p>
      )}
      <h3>Chance to win</h3>
      <details open={likely !== favorite || undefined}>
        <summary>How the path and chances differ</summary>
        <p>
          The most likely path picks the favorite in every match. Title chances
          count upsets and second chances across 5,000 simulated playoffs.
          Finals are best of three.
        </p>
      </details>
      <ul>
        {odds.title.map((p, i) => (
          <li key={alliances[i]?.join("-")}>
            Alliance {i + 1}: {Math.round(p * 100)}% title,{" "}
            {Math.round((odds.finals[i] ?? 0) * 100)}% finals
          </li>
        ))}
      </ul>
    </section>
  );
}
