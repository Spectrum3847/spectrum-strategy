import { dataAuth } from "../firebase/client";
import { pushWorkerOrigin } from "../push/config";
import { createRelayChat } from "./relay";
import { createHubSignaling } from "./relayHub";

const signaling = createHubSignaling({
  origin: pushWorkerOrigin,
  token: async () => dataAuth.currentUser?.getIdToken(),
});
export const newRelayChat = () => createRelayChat(signaling);
