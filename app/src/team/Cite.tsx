import { Link } from "react-router";
import { matchPath, parseMatchKey } from "../data/matchKey";
import type { MatchCite } from "./summary";

export function Cite({ cite }: { cite: MatchCite }) {
  return parseMatchKey(cite.key) ? (
    <Link className="team-cite" to={matchPath(cite.key)}>
      {cite.label}
    </Link>
  ) : (
    <span className="team-cite">{cite.label}</span>
  );
}
