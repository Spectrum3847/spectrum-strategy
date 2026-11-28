export type ThemeChoice = "auto" | "light" | "dark";

const key = "ss.theme";

export function getTheme(): ThemeChoice {
  try {
    const value = localStorage.getItem(key);
    return value === "light" || value === "dark" ? value : "auto";
  } catch {
    return "auto";
  }
}

export function applyTheme(choice: ThemeChoice) {
  const root = document.documentElement;
  if (choice === "auto") root.removeAttribute("data-theme");
  else root.setAttribute("data-theme", choice);
  try {
    if (choice === "auto") localStorage.removeItem(key);
    else localStorage.setItem(key, choice);
  } catch {
  }
}
