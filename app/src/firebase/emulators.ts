import { type Auth, connectAuthEmulator } from "firebase/auth";
import { connectFirestoreEmulator, type Firestore } from "firebase/firestore";

export const emulatorProjects = {
  data: "demo-spectrum-e2e",
  central: "demo-spectrum-central",
};
const host = "127.0.0.1";
const ports = { auth: 19099, firestore: 18080 };

export function connectEmulators(auths: Auth[], db: Firestore) {
  for (const auth of auths) {
    connectAuthEmulator(auth, `http://${host}:${ports.auth}`, {
      disableWarnings: true,
    });
  }
  connectFirestoreEmulator(db, host, ports.firestore);
}
