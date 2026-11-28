export const dataConfig = {
  apiKey: "AIzaSyCgatjO0H0C7pl3Lh0_tfcbFbDV-Xru7yg",
  appId: "1:568915292867:web:c00f045cbc27452aeaa876",
  messagingSenderId: "568915292867",
  projectId: "frcspectrumstrategy",
  authDomain: "frcspectrumstrategy.firebaseapp.com",
  storageBucket: "frcspectrumstrategy.firebasestorage.app",
};

export const centralConfig = {
  apiKey: "AIzaSyANgQ_R01hyMdoyKQqTPVIHI69GzdedYIE",
  appId: "1:122861436864:web:d304baca619c6b82c1d225",
  messagingSenderId: "122861436864",
  projectId: "spectrumtasks-81c63",
  authDomain: "spectrumtasks-81c63.firebaseapp.com",
  storageBucket: "spectrumtasks-81c63.firebasestorage.app",
};

export const appKey =
  import.meta.env.VITE_SPECTRUM_APP_KEY ?? "spectrumstrategy";
export const customTokenCallable = "getCustomToken";

export const emulatorsOn = import.meta.env.VITE_FIREBASE_EMULATORS === "true";
