import { useId, useState } from "react";
import {
  countOf,
  type FilterId,
  type FilterResults,
  filterDefs,
  filterGroups,
} from "./filters";

export function TeamFilterBar({
  results,
  active,
  shown,
  showPit,
  onToggle,
  onClear,
}: {
  results: FilterResults;
  active: FilterId[];
  shown: number;
  showPit: boolean;
  onToggle: (id: FilterId) => void;
  onClear: () => void;
}) {
  const [open, setOpen] = useState(active.length > 0);
  const panel = useId();
  return (
    <div className="teams-filters">
      <button
        type="button"
        className="btn"
        aria-expanded={open}
        aria-controls={panel}
        onClick={() => setOpen((o) => !o)}
      >
        {active.length === 0 ? "Filters" : `Filters (${active.length} on)`}
      </button>
      <div id={panel} hidden={!open} className="teams-filter-groups">
        {filterGroups.map((group) => {
          const defs = filterDefs.filter(
            (d) => d.group === group.id && (showPit || !d.needsPit),
          );
          if (defs.length === 0) return null;
          return (
            <fieldset key={group.id} className="teams-filter-group">
              <legend className="label">{group.label}</legend>
              <div className="teams-filter-chips">
                {defs.map((d) => (
                  <button
                    key={d.id}
                    type="button"
                    className="chip"
                    aria-pressed={active.includes(d.id)}
                    title={d.rule}
                    aria-describedby={`${panel}-${d.id}`}
                    onClick={() => onToggle(d.id)}
                  >
                    {`${d.label} (${countOf(results, d.id)})`}
                  </button>
                ))}
              </div>
              {defs.map((d) => (
                <span key={d.id} id={`${panel}-${d.id}`} className="sr-only">
                  {d.rule}
                </span>
              ))}
            </fieldset>
          );
        })}
      </div>
      {active.length > 0 && (
        <div className="teams-filter-state">
          <p role="status">
            <strong>{`${shown} of ${results.total} teams`}</strong>
          </p>
          <button type="button" className="btn" onClick={onClear}>
            Clear filters
          </button>
          {shown === 0 && (
            <p className="secondary">
              No team passes every selected filter. Turn one off, or clear them
              all to see the full list.
            </p>
          )}
        </div>
      )}
    </div>
  );
}
