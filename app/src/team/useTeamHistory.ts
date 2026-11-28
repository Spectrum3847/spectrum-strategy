import { useEffect, useState } from "react";
import { emptyHistory, loadHistory, type TeamHistory } from "./history";

export interface HistoryState {
  loading: boolean;
  history: TeamHistory;
}

export function useTeamHistory(team: number, enabled: boolean): HistoryState {
  const [state, setState] = useState<HistoryState>({
    loading: enabled,
    history: emptyHistory,
  });
  useEffect(() => {
    let live = true;
    if (!enabled || team === 0) {
      setState({ loading: false, history: emptyHistory });
      return;
    }
    setState({ loading: true, history: emptyHistory });
    void loadHistory(team).then((history) => {
      if (live) setState({ loading: false, history });
    });
    return () => {
      live = false;
    };
  }, [team, enabled]);
  return state;
}
