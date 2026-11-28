import { Link } from "react-router";
import { canOpenTeamPage } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import "./ui.css";

export function TeamLink({ team }: { team: number }) {
  const roles = useRoles();
  if (roles.status === "ready" && canOpenTeamPage(roles.roles)) {
    return (
      <Link className="team-ref" to={`/teams/${team}`}>
        {team}
      </Link>
    );
  }
  return <span className="team-ref">{team}</span>;
}
