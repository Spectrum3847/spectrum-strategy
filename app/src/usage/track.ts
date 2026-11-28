import { doc, setDoc } from "firebase/firestore";
import { useEffect } from "react";
import { useLocation } from "react-router";
import { db } from "../firebase/client";
import { emulatorsOn } from "../firebase/config";
import { isTraining } from "../training/session";
import { deviceId, sharingStore } from "./prefs";
import { createTelemetry, createTracker } from "./telemetry";

const telemetry = createTelemetry({
  enabled: sharingStore.get,
  suppressed: () => emulatorsOn || isTraining(),
  deviceId,
  env: () => ({
    appVersion: `${__APP_VERSION__} (${__BUILD_SHA__} ${__BUILD_TIME__.slice(0, 10)})`,
    platform: "web",
    osVersion: "",
    locale: navigator.language,
  }),
  write: (id, data) => setDoc(doc(db, "telemetry", id), data),
  now: () => new Date(),
  newId: () => crypto.randomUUID(),
});

const tracker = createTracker(telemetry.log);

export function useUsageTracking() {
  const { pathname } = useLocation();
  useEffect(() => tracker.visit(pathname), [pathname]);
}
