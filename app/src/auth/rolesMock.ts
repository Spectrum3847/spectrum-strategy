import type { ReactNode } from "react";
import type { Role } from "./roles";
import type { RolesContext } from "./rolesContext";

export const ready = (...roles: Role[]): RolesContext => ({
  status: "ready",
  uid: "u1",
  roles,
  displayName: "Scout A",
  identityUids: ["u1"],
  retry: () => undefined,
});

let current: RolesContext = ready("strategy");

export const setRoles = (state: RolesContext) => {
  current = state;
};

export const rolesModule = {
  RolesProvider: ({ children }: { children: ReactNode }) => children,
  useRoles: () => current,
};
