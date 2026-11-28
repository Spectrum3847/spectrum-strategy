import { useCallback, useRef, useState, useSyncExternalStore } from "react";
import { useAuth } from "../auth/AuthProvider";
import { useRoles } from "../auth/rolesContext";
import { ModeTabs } from "../forms/ModeTabs";
import { dismissItem } from "../outbox/outbox";
import { useOutbox } from "../outbox/useOutbox";
import type { ShiftRosterEntry } from "../scout/credit";
import { useScoutData } from "../scout/ScoutData";
import { qualMatches } from "../scout/schedule";
import type { Delivery } from "./MyShifts";
import { playedThrough } from "./mine";
import { PitScheduleSection } from "./PitSchedule";
import { rebuildWithScouts } from "./rebuild";
import { fetchProfiles } from "./remote";
import { canEditShifts, resolveRoster } from "./roster";
import { ShiftsView } from "./ShiftsView";
import { blank, maxRoster } from "./schedule";
import { useShiftData } from "./useShiftData";
import { answerTrade, requestTrade } from "./write";

const subscribeOnline = (notify: () => void) => {
  window.addEventListener("online", notify);
  window.addEventListener("offline", notify);
  return () => {
    window.removeEventListener("online", notify);
    window.removeEventListener("offline", notify);
  };
};

const unlinkedNotice = (
  profilesLoaded: boolean,
  unmatched: string[],
  ambiguous: string[],
) =>
  [
    profilesLoaded
      ? ""
      : "The member list could not be loaded, so no name is linked to an account.",
    unmatched.length > 0
      ? `No matching account: ${unmatched.join(", ")}. Each name has to match that member's account name exactly.`
      : "",
    ambiguous.length > 0
      ? `Name shared by several members: ${ambiguous.join(", ")}.`
      : "",
  ]
    .filter(Boolean)
    .join(" ");

export function Shifts() {
  const auth = useAuth();
  const data = useScoutData();
  const outbox = useOutbox();
  const online = useSyncExternalStore(
    subscribeOnline,
    () => navigator.onLine,
    () => true,
  );
  const signedIn = auth.status === "signed-in";
  const shiftData = useShiftData(data.eventKey, signedIn, outbox);
  const roles = useRoles();
  const [notice, setNotice] = useState<string | null>(null);
  const latest = useRef(shiftData.shifts);
  latest.current = shiftData.shifts;

  const deliveryOf = useCallback(
    (path: string): Delivery | undefined => {
      const item = outbox.find((i) => i.path === path);
      if (!item) return undefined;
      return {
        id: item.id,
        status: item.status,
        ...(item.error ? { error: item.error } : {}),
      };
    },
    [outbox],
  );

  const report = (error: unknown) =>
    setNotice(
      error instanceof Error
        ? error.message
        : "The change could not be saved on this device.",
    );

  const onInputNames = async (names: string[], matchCount: number) => {
    setNotice(null);
    const profiles = await fetchProfiles();
    const { roster, ambiguous, unmatched } = resolveRoster(names, profiles);
    const first = shiftData.shifts?.authorUid
      ? {
          uid: shiftData.shifts.authorUid,
          displayName: shiftData.shifts.authorDisplayName,
        }
      : { uid: auth.uid ?? "", displayName: auth.displayName ?? "" };
    try {
      await shiftData.save(blank({ roster, matchCount, author: first }));
    } catch (error) {
      return report(error);
    }
    const problems = unlinkedNotice(profiles !== null, unmatched, ambiguous);
    if (problems) {
      setNotice(
        `${problems} Those scouts cannot see their own shifts or trade until the names are fixed.`,
      );
    }
  };

  const onRebuild = async (from: number, names: string[]) => {
    setNotice(null);
    let scouts: ShiftRosterEntry[] = [];
    if (names.length > 0) {
      const profiles = await fetchProfiles();
      const { roster, ambiguous, unmatched } = resolveRoster(names, profiles);
      scouts = roster;
      const problems = unlinkedNotice(profiles !== null, unmatched, ambiguous);
      if (problems) {
        setNotice(
          `${problems} Those scouts cannot see their own shifts or trade until the names are fixed.`,
        );
      }
    }
    const current = latest.current;
    if (!current) return null;
    const result = rebuildWithScouts(current, from, scouts);
    if (!result) {
      setNotice(`The roster can hold ${maxRoster} names at most.`);
      return null;
    }
    try {
      await shiftData.save(result.next);
    } catch (error) {
      report(error);
      return null;
    }
    return result.summary;
  };

  return (
    <>
      <ModeTabs />
      <ShiftsView
        eventKey={data.eventKey}
        auth={auth.status}
        uid={auth.uid}
        name={roles.status === "ready" ? roles.displayName : ""}
        online={online}
        load={shiftData.load}
        fromCache={shiftData.fromCache}
        shifts={shiftData.shifts}
        trades={shiftData.trades}
        played={playedThrough(data.schedule, data.entries)}
        qualCount={qualMatches(data.schedule).length}
        canEdit={roles.status === "ready" && canEditShifts(roles.roles)}
        deliveryOf={deliveryOf}
        onDismiss={dismissItem}
        onRequestTrade={(block, target) => {
          if (!auth.uid) return;
          requestTrade({
            eventKey: data.eventKey,
            requester: { uid: auth.uid, displayName: auth.displayName ?? "" },
            target,
            block,
          }).catch(report);
        }}
        onAnswerTrade={(trade, status) =>
          answerTrade(trade, status).catch(report)
        }
        onSave={(next) => {
          setNotice(null);
          shiftData.save(next).catch(report);
        }}
        onInputNames={onInputNames}
        onRebuild={onRebuild}
        notice={notice}
        pit={<PitScheduleSection eventKey={data.eventKey} uid={auth.uid} />}
      />
    </>
  );
}
