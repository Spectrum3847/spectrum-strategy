import { NavLink } from "react-router";
import { isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import "./forms.css";

const modes = [
  { to: "/scout", label: "Match", end: true },
  { to: "/scout/pit", label: "Pit", end: false },
  { to: "/scout/prescout", label: "Prescout", end: false },
  { to: "/scout/shifts", label: "Shifts", end: false },
  { to: "/scout/trex", label: "T-REx", end: false },
  { to: "/scout/accuracy", label: "Accuracy", end: false, lead: true },
];

export function ModeTabs() {
  const roles = useRoles();
  const lead = roles.status === "ready" && isLead(roles.roles);
  return (
    <nav className="mode-tabs" aria-label="Scouting form">
      {modes
        .filter((m) => lead || !m.lead)
        .map((m) => (
          <NavLink key={m.to} to={m.to} end={m.end} className="mode-tab">
            {m.label}
          </NavLink>
        ))}
    </nav>
  );
}
