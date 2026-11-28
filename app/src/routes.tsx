import type { RouteObject } from "react-router";
import { Accuracy } from "./accuracy/AccuracyPage";
import { PredictionCheck } from "./accuracy/PredictionCheck";
import { AiChat } from "./assistant/ChatPage";
import { BoardRoute } from "./board/BoardRoute";
import { Boards } from "./board/BoardsPage";
import { Database } from "./database/DatabasePage";
import { Help, HelpDoc } from "./help/Help";
import { Match } from "./match/MatchPage";
import { Picks } from "./picks/PicksPage";
import { PitFormRoute, PitListRoute } from "./pit/PitScreens";
import { Playoffs } from "./playoffs/PlayoffsPage";
import {
  PrescoutFormRoute,
  PrescoutListRoute,
  PrescoutTeamRoute,
} from "./prescout/PrescoutScreens";
import { Now } from "./routes/Now";
import { NotFound } from "./routes/Placeholders";
import { Scan } from "./routes/Scan";
import { Scout } from "./routes/Scout";
import { Settings } from "./routes/Settings";
import { Shell } from "./routes/Shell";
import { Schedule } from "./schedule/Schedule";
import { Shifts } from "./shifts/Shifts";
import { Team } from "./team/TeamPage";
import { Analysis } from "./teams/AnalysisPage";
import { Compare } from "./teams/ComparePage";
import { Teams } from "./teams/TeamsPage";
import { TrexAssignments } from "./trex/TrexAssignments";
import { TrexDatabase } from "./trex/TrexDatabase";
import { TrexReportForm } from "./trex/TrexReportForm";
import { Usage } from "./usage/UsagePage";
import { Users } from "./users/UsersPage";

export const routes: RouteObject[] = [
  {
    element: <Shell />,
    children: [
      { index: true, element: <Now /> },
      { path: "scout", element: <Scout /> },
      { path: "scout/scan", element: <Scan /> },
      { path: "scout/shifts", element: <Shifts /> },
      { path: "scout/accuracy", element: <Accuracy /> },
      { path: "scout/accuracy/predictions", element: <PredictionCheck /> },
      { path: "scout/pit", element: <PitListRoute /> },
      { path: "scout/pit/:team", element: <PitFormRoute /> },
      { path: "scout/pit/:team/:id", element: <PitFormRoute /> },
      { path: "scout/prescout", element: <PrescoutListRoute /> },
      { path: "scout/prescout/:team", element: <PrescoutTeamRoute /> },
      { path: "scout/prescout/:team/:id", element: <PrescoutFormRoute /> },
      { path: "picks", element: <Picks /> },
      { path: "picks/playoffs", element: <Playoffs /> },
      { path: "database", element: <Database /> },
      { path: "ai", element: <AiChat /> },
      { path: "schedule", element: <Schedule /> },
      { path: "scout/trex", element: <TrexReportForm /> },
      { path: "scout/trex/reports", element: <TrexDatabase /> },
      { path: "scout/trex/assignments", element: <TrexAssignments /> },
      { path: "settings", element: <Settings /> },
      { path: "help", element: <Help /> },
      { path: "help/:doc", element: <HelpDoc /> },
      { path: "users", element: <Users /> },
      { path: "usage", element: <Usage /> },
      { path: "teams", element: <Teams /> },
      { path: "teams/analysis", element: <Analysis /> },
      { path: "teams/compare", element: <Compare /> },
      { path: "teams/:team", element: <Team /> },
      { path: "matches/:key", element: <Match /> },
      { path: "boards", element: <Boards /> },
      { path: "boards/:id", element: <BoardRoute /> },
      { path: "*", element: <NotFound />, handle: { open: true } },
    ],
  },
];
