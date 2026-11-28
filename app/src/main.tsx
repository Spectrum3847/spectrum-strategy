import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { createBrowserRouter } from "react-router";
import { RouterProvider } from "react-router/dom";
import { AuthProvider } from "./auth/AuthProvider";
import { startOutbox } from "./outbox/outbox";
import { startPhotoQueue } from "./photos/service";
import { routes } from "./routes";
import { applyTheme, getTheme } from "./theme";
import "./styles/tokens.css";
import "./styles/app.css";

applyTheme(getTheme());
startOutbox().catch((error: unknown) => {
  console.error("Outbox failed to start", error);
});
startPhotoQueue();
navigator.storage?.persist?.().catch(() => undefined);

const router = createBrowserRouter(routes);
const root = document.getElementById("root");
if (!root) throw new Error("missing #root");

createRoot(root).render(
  <StrictMode>
    <AuthProvider>
      <RouterProvider router={router} />
    </AuthProvider>
  </StrictMode>,
);
