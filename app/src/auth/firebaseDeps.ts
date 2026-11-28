import {
  GoogleAuthProvider,
  signInWithCustomToken,
  signInWithPopup,
} from "firebase/auth";
import { httpsCallable } from "firebase/functions";
import { centralAuth, centralFunctions, dataAuth } from "../firebase/client";
import { appKey, customTokenCallable } from "../firebase/config";
import type { HandshakeDeps } from "./handshake";

const callableTimeoutMs = 90_000;

export const firebaseDeps: HandshakeDeps = {
  appKey,
  async signInWithGoogle() {
    await signInWithPopup(centralAuth, new GoogleAuthProvider());
  },
  async getCustomToken(targetApp) {
    const callable = httpsCallable<
      { targetApp: string },
      { customToken: string }
    >(centralFunctions, customTokenCallable, { timeout: callableTimeoutMs });
    const result = await callable({ targetApp });
    return { customToken: result.data.customToken };
  },
  async signInWithCustomToken(token) {
    await signInWithCustomToken(dataAuth, token);
  },
  async signOutCentral() {
    await centralAuth.signOut();
  },
};
