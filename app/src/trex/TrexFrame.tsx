import type { ReactNode } from "react";
import { NavLink } from "react-router";
import { useTbaEvent } from "../data/useTbaEvent";
import { ListHead } from "../forms/ListParts";
import { ModeTabs } from "../forms/ModeTabs";
import { useOutbox } from "../outbox/useOutbox";
import { useOnline } from "../ui/useOnline";
import { unsentReports } from "./delivery";
import "./trex.css";

const views = [
  { to: "/scout/trex", label: "Report", end: true },
  { to: "/scout/trex/reports", label: "Reports", end: false },
  { to: "/scout/trex/assignments", label: "Assignments", end: false },
];

export function TrexFrame({ children }: { children: ReactNode }) {
  const { eventKey } = useTbaEvent();
  const online = useOnline();
  const unsent = unsentReports(useOutbox());
  return (
    <div className="forms-page trex">
      <ModeTabs />
      <ListHead
        title="T-REx"
        eventKey={eventKey}
        online={online}
        unsent={unsent}
      />
      <nav className="trex-views" aria-label="T-REx">
        {views.map((v) => (
          <NavLink key={v.to} to={v.to} end={v.end} className="trex-view">
            {v.label}
          </NavLink>
        ))}
      </nav>
      {children}
    </div>
  );
}
