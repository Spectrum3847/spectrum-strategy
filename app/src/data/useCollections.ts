import { useMemo } from "react";
import { useAuth } from "../auth/AuthProvider";
import type { ScoutConfig } from "../scout/config";
import { readCache, writeCache } from "./cache";
import {
  bundledConfig,
  configDocId,
  type FormKind,
  replacesCached,
  resolveConfig,
} from "./formConfig";
import type { PitEntry, PrescoutEntry, TrexReport } from "./parse";
import {
  watchFormConfig,
  watchPitEntries,
  watchPrescoutEntries,
  watchTrexReports,
} from "./remote";
import {
  createStore,
  type Feed,
  feedStore,
  idleFeed,
  storeFor,
  useStore,
} from "./store";

function useSignedIn() {
  return useAuth().status === "signed-in";
}

export function usePitEntries(): Feed<PitEntry> {
  const store = useSignedIn()
    ? storeFor("pit", () => feedStore<PitEntry>(watchPitEntries))
    : null;
  return useStore(store, idleFeed);
}

export function usePrescoutEntries(): Feed<PrescoutEntry> {
  const store = useSignedIn()
    ? storeFor("prescout", () => feedStore<PrescoutEntry>(watchPrescoutEntries))
    : null;
  return useStore(store, idleFeed);
}

export function useTrexReports(): Feed<TrexReport> {
  const store = useSignedIn()
    ? storeFor("trex", () => feedStore<TrexReport>(watchTrexReports))
    : null;
  return useStore(store, idleFeed);
}

const cacheKey = (kind: FormKind) => `ss.config.${kind}`;

export function useFormConfig(kind: FormKind): ScoutConfig {
  const signedIn = useSignedIn();
  const store = signedIn
    ? storeFor(`config:${kind}`, () =>
        createStore<string | null>(null, (set) =>
          watchFormConfig(configDocId[kind], (json) => {
            if (replacesCached(readCache<string>(cacheKey(kind)), json)) {
              writeCache(cacheKey(kind), json);
            }
            set(json);
          }),
        ),
      )
    : null;
  const remote = useStore(store, null);
  return useMemo(
    () =>
      resolveConfig(bundledConfig[kind], [
        readCache<string>(cacheKey(kind)),
        remote,
      ]),
    [kind, remote],
  );
}
