import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import {
  initializeFirestore,
  persistentLocalCache,
  persistentMultipleTabManager,
} from "firebase/firestore";
import { getFunctions } from "firebase/functions";
import { centralConfig, dataConfig, emulatorsOn } from "./config";
import { connectEmulators, emulatorProjects } from "./emulators";

const dataApp = initializeApp(
  emulatorsOn
    ? { ...dataConfig, projectId: emulatorProjects.data }
    : dataConfig,
);
const centralApp = initializeApp(
  emulatorsOn
    ? { ...centralConfig, projectId: emulatorProjects.central }
    : centralConfig,
  "central",
);

export const dataAuth = getAuth(dataApp);
export const centralAuth = getAuth(centralApp);
export const centralFunctions = getFunctions(centralApp);

export const db = initializeFirestore(dataApp, {
  localCache: persistentLocalCache({
    tabManager: persistentMultipleTabManager(),
  }),
});

if (emulatorsOn) connectEmulators([dataAuth, centralAuth], db);
