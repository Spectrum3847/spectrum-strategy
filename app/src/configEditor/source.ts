import { doc, onSnapshot } from "firebase/firestore";
import { useEffect, useMemo, useState } from "react";
import bundledPit from "../../../assets/pit_scout_config_default.json";
import bundledPrescout from "../../../assets/prescout_config_default.json";
import bundledScout from "../../../assets/scout_config_default.json";
import { useAuth } from "../auth/AuthProvider";
import { readCache } from "../data/cache";
import { db } from "../firebase/client";
import { enqueueWrite } from "../outbox/outbox";
import { configCache } from "../scout/local";
import { pickActive } from "./active";
import { configPath, type Doc, docIdOf, type FormId, formName } from "./doc";

const bundled: Record<FormId, Doc> = {
  scout: bundledScout,
  pit: bundledPit,
  prescout: bundledPrescout,
};

const deviceCopy = (form: FormId) =>
  form === "scout" ? configCache.get() : readCache<string>(`ss.config.${form}`);

export interface ConfigSource {
  active: Doc;
  teamCopyKnown: boolean;
}

export function useConfigSource(form: FormId): ConfigSource {
  const signedIn = useAuth().status === "signed-in";
  const [remote, setRemote] = useState<{
    form: FormId;
    json: string | null;
    fromServer: boolean;
  } | null>(null);
  useEffect(() => {
    if (!signedIn) return;
    return onSnapshot(
      doc(db, "appConfig", docIdOf[form]),
      (snap) => {
        const json: unknown = snap.data()?.configJson;
        setRemote({
          form,
          json: typeof json === "string" ? json : null,
          fromServer: !snap.metadata.fromCache,
        });
      },
      () => undefined,
    );
  }, [form, signedIn]);
  const current = remote?.form === form ? remote : null;
  const json = current?.json ?? null;
  const active = useMemo(
    () => pickActive(bundled[form], [deviceCopy(form), json]),
    [form, json],
  );
  return { active, teamCopyKnown: current?.fromServer === true };
}

export function saveConfig(form: FormId, configJson: string) {
  return enqueueWrite(
    configPath(form),
    { configJson, updatedAt: new Date().toISOString() },
    `${formName[form]} config`,
  );
}
