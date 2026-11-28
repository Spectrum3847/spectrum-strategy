import { useRoles } from "../auth/rolesContext";
import { NotAvailable } from "../ui/AccessScreens";
import {
  busiestDay,
  freshness,
  isEmptyRollup,
  type UsageCount,
  type UsageDay,
  type UsageRollup,
} from "./rollup";
import { type RollupReader, useRollup } from "./useRollup";
import "./usage.css";

function Stat({ value, label }: { value: number; label: string }) {
  return (
    <div className="usage-stat">
      <strong>{value}</strong>
      <span className="secondary">{label}</span>
    </div>
  );
}

function Bars({
  title,
  note,
  counts,
}: {
  title: string;
  note: string;
  counts: UsageCount[];
}) {
  if (counts.length === 0) return null;
  const top = counts[0]?.count ?? 0;
  return (
    <section className="usage-section">
      <h2>{title}</h2>
      <p className="secondary">{note}</p>
      <table className="usage-table">
        <thead className="sr-only">
          <tr>
            <th scope="col">Name</th>
            <th scope="col">Bar</th>
            <th scope="col">Count</th>
          </tr>
        </thead>
        <tbody>
          {counts.map((row, i) => (
            <tr key={row.name}>
              <th scope="row">{row.name}</th>
              <td aria-hidden="true">
                <span
                  className="usage-bar"
                  data-leading={i === 0}
                  style={{
                    width: `${top <= 0 ? 0 : Math.max(2, (row.count / top) * 100)}%`,
                  }}
                />
              </td>
              <td className="usage-count">{row.count}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}

function Daily({ days }: { days: UsageDay[] }) {
  if (days.length === 0) return null;
  const busiest = busiestDay(days);
  return (
    <section className="usage-section">
      <h2>Events per day</h2>
      <p className="secondary">
        Busiest day: {busiest}. A competition week should stand out.
      </p>
      <div className="usage-days" aria-hidden="true">
        {days.map((day) => (
          <span
            key={day.date}
            title={`${day.date}: ${day.count}`}
            style={{
              height: `${busiest <= 0 ? 2 : Math.max(2, (day.count / busiest) * 100)}%`,
            }}
          />
        ))}
      </div>
      <details>
        <summary>Show the numbers</summary>
        <table className="usage-table">
          <thead>
            <tr>
              <th scope="col">Day (UTC)</th>
              <th scope="col" className="usage-count">
                Events
              </th>
            </tr>
          </thead>
          <tbody>
            {days.map((day) => (
              <tr key={day.date}>
                <th scope="row">{day.date}</th>
                <td className="usage-count">{day.count}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </details>
    </section>
  );
}

function Report({ rollup }: { rollup: UsageRollup }) {
  return (
    <>
      <div className="usage-stats">
        <Stat value={rollup.eventsCounted} label="events" />
        <Stat
          value={rollup.deviceCount}
          label={rollup.deviceCount === 1 ? "device" : "devices"}
        />
        <Stat value={rollup.windowDays} label="days" />
      </div>
      <p className="secondary">{freshness(rollup.updatedAt)}</p>
      <Bars
        title="Tabs opened"
        note="Which screens people actually go to."
        counts={rollup.tabs}
      />
      <Bars
        title="Platforms"
        note="A desktop-only feature reads as unused without this."
        counts={rollup.platforms}
      />
      <Bars
        title="App versions"
        note="Who is still on an old build."
        counts={rollup.appVersions}
      />
      <Daily days={rollup.daily} />
    </>
  );
}

function Message({
  title,
  detail,
  onRetry,
}: {
  title: string;
  detail: string;
  onRetry: () => void;
}) {
  return (
    <div className="notice" role="status">
      <strong>{title}</strong>
      <span>{detail}</span>
      <button type="button" className="btn" onClick={onRetry}>
        Try again
      </button>
    </div>
  );
}

export function Usage({ read }: { read?: RollupReader }) {
  const roles = useRoles();
  const { state, reload } = useRollup(read);
  if (roles.status !== "ready" || !roles.roles.includes("developer")) {
    return <NotAvailable who="developer accounts" />;
  }
  return (
    <div className="usage">
      <h1>Usage</h1>
      {state.status === "loading" && <p className="secondary">Loading.</p>}
      {state.status === "error" && (
        <Message
          title="No usage data"
          detail={state.message}
          onRetry={reload}
        />
      )}
      {state.status === "ready" &&
        (isEmptyRollup(state.rollup) ? (
          <Message
            title="Nothing recorded yet"
            detail={`The rollup ran but counted no events in the last ${state.rollup.windowDays} days.`}
            onRetry={reload}
          />
        ) : (
          <Report rollup={state.rollup} />
        ))}
    </div>
  );
}
