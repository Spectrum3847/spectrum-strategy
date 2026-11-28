import { useScoutData } from "../scout/ScoutData";
import { useTaken } from "./draftStore";
import "./picks.css";

export function PickedMark({ team }: { team: number }) {
  const { eventKey } = useScoutData();
  const label = useTaken(eventKey)[team];
  return label ? <span className="picked">{label}</span> : null;
}
