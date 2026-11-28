import { createContext, useContext } from "react";

export const TourContext = createContext<{ open: () => void } | null>(null);

export const useTour = () => useContext(TourContext);
