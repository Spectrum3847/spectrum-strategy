import {
  addStroke,
  type Board,
  canRedo,
  canUndo,
  clearAll,
  clearPhase,
  emptyHistory,
  erase,
  type Hit,
  moveMarker,
  moveTeamSide,
  placeAll,
  placeLabel,
  placeMarker,
  type Robot,
  redo,
  setNote,
  teamsPlaced,
  undo,
  updateLabel,
} from "./edit";
import type { LocalRecord } from "./local";
import {
  type Author,
  boardSides,
  type Label,
  type Marker,
  newSession,
  type Phase,
  type Point,
  parseSession,
  penColor,
  type Session,
  sessionDoc,
  sessionJson,
  type Tool,
} from "./model";
import { decideRemote } from "./sync";

export interface Deps {
  load(): Promise<LocalRecord | null>;
  save(record: LocalRecord): Promise<void>;
  enqueue(doc: Record<string, unknown>): Promise<unknown>;
  unsent(id: string): boolean;
  discard(id: string): void;
  now(): number;
  newId(): string;
  debounceMs: number;
}

export interface Context {
  eventKey: string;
  matchNumber: number;
  alliance: string;
  robots: Robot[];
  fieldId: string;
}

export interface BoardState {
  ready: boolean;
  session: Session;
  robots: Robot[];
  practice: boolean;
  phase: Phase;
  tool: Tool;
  team: number | null;
  canUndo: boolean;
  canRedo: boolean;
  local: "saved" | "saving" | "failed";
  handed: boolean;
  hasBoard: boolean;
  remote: "none" | "server" | "cache";
  conflict: Session | null;
}

type Listener = () => void;

export class BoardController {
  private board: Board;
  private phase: Phase = "auton";
  private tool: Tool = "draw";
  private team: number | null = null;
  private queuedMs = 0;
  private touched = false;
  private conflict: Session | null = null;
  private practice = false;
  private started = false;
  private ready = false;
  private loaded = false;
  private record: LocalRecord | null = null;
  private remote: Session | null = null;
  private remoteReady = false;
  private remoteCache = false;
  private waited = false;
  private drawing = false;
  private author: Author = { uid: "", displayName: "" };
  private timer: ReturnType<typeof setTimeout> | null = null;
  private chain: Promise<void> = Promise.resolve();
  private inFlight = 0;
  private lastSaveOk = true;
  private readonly listeners = new Set<Listener>();
  private snapshot: BoardState;

  constructor(
    private readonly deps: Deps,
    private readonly ctx: Context,
  ) {
    this.board = {
      session: this.draft(),
      history: emptyHistory(),
    };
    this.snapshot = this.state();
  }

  subscribe = (listener: Listener): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): BoardState => this.snapshot;

  start(): Promise<void> {
    return this.deps.load().then(
      (record) => {
        this.record = record;
        this.loaded = true;
        this.resolve();
      },
      (error: unknown) => {
        console.error("Strategy board: device copy not readable", error);
        this.lastSaveOk = false;
        this.loaded = true;
        this.resolve();
      },
    );
  }

  proceed() {
    this.waited = true;
    this.resolve();
  }

  setAuthor(author: Author) {
    this.author = author;
    if (this.started && this.pending()) this.schedule(0);
  }

  setRemote(remote: Session | null, ready: boolean, fromCache: boolean) {
    this.remote = remote;
    this.remoteReady = ready;
    this.remoteCache = fromCache;
    if (!this.started) {
      this.resolve();
      return;
    }
    this.reconcile();
    this.emit();
  }

  selectPhase(phase: Phase) {
    this.phase = phase;
    this.team = null;
    this.emit();
  }

  selectTool(tool: Tool) {
    this.tool = tool;
    this.emit();
  }

  selectTeam(team: number) {
    this.team = team;
    this.emit();
  }

  setDrawing(on: boolean) {
    this.drawing = on;
    if (!on) {
      this.reconcile();
      this.emit();
    }
  }

  commitStroke(points: Point[], legend: boolean) {
    if (points.length < (legend ? 1 : 2)) return;
    this.commit(
      addStroke(
        this.board,
        this.phase,
        { phase: this.phase, legend, color: penColor, points },
        this.deps.now(),
      ),
    );
  }

  placeAt(point: Point) {
    const team = this.state().team;
    const robot = this.robots().find((r) => r.team === team);
    if (!robot) return;
    const marker: Marker = {
      phase: this.phase,
      position: point,
      team: robot.team,
      label: null,
      alliance: robot.side === "red" ? "Red" : "Blue",
    };
    const next = placeMarker(this.board, this.phase, marker, this.deps.now());
    if (next !== this.board) this.commit(next);
  }

  placeAll() {
    this.commit(
      placeAll(this.board, this.phase, this.robots(), this.deps.now()),
    );
  }

  setPractice(on: boolean) {
    if (on === this.practice) return;
    this.practice = on;
    this.emit();
  }

  moveTeamSide(team: number) {
    if (!this.practice) return;
    const next = moveTeamSide(this.board, team, this.deps.now());
    if (next !== this.board) this.commit(next);
  }

  moveMarker(marker: Marker, to: Point) {
    const next = moveMarker(
      this.board,
      this.phase,
      marker,
      to,
      this.deps.now(),
    );
    if (next !== this.board) this.commit(next);
  }

  placeLabel(label: Label) {
    this.commit(placeLabel(this.board, this.phase, label, this.deps.now()));
  }

  updateLabel(label: Label, updated: Label) {
    const next = updateLabel(
      this.board,
      this.phase,
      label,
      updated,
      this.deps.now(),
    );
    if (next !== this.board) this.commit(next);
  }

  erase(hit: Hit, fresh: boolean) {
    const next = erase(this.board, this.phase, hit, fresh, this.deps.now());
    if (next !== this.board) this.commit(next);
  }

  clearPhase() {
    this.commit(clearPhase(this.board, this.phase, this.deps.now()));
  }

  clearAll() {
    this.commit(clearAll(this.board, this.deps.now()));
  }

  setNote(note: string) {
    this.commit(setNote(this.board, this.phase, note, this.deps.now()));
  }

  undo() {
    const next = undo(this.board, this.phase, this.deps.now());
    if (next !== this.board) this.commit(next);
  }

  redo() {
    const next = redo(this.board, this.phase, this.deps.now());
    if (next !== this.board) this.commit(next);
  }

  loadTheirs() {
    if (this.conflict) this.adopt(this.conflict);
  }

  keepMine() {
    const theirs = this.conflict;
    if (!theirs) return;
    this.conflict = null;
    const session = this.board.session;
    this.board = {
      ...this.board,
      session: {
        ...session,
        updatedMs: Math.max(
          this.deps.now(),
          theirs.updatedMs + 1,
          session.updatedMs,
        ),
      },
    };
    this.touched = true;
    this.persist();
    this.handoff();
    this.emit();
  }

  flush() {
    if (this.timer !== null) this.handoff();
  }

  dispose() {
    this.flush();
    this.listeners.clear();
  }

  private draft(): Session {
    const oursSide = this.ctx.alliance === "Blue" ? "blue" : "red";
    return newSession({
      id: this.deps.newId(),
      eventKey: this.ctx.eventKey,
      matchNumber: this.ctx.matchNumber,
      alliance: this.ctx.alliance,
      teamNumbers: this.ctx.robots.map((r) => r.team),
      opponentTeams: this.ctx.robots
        .filter((r) => r.side !== oursSide)
        .map((r) => r.team),
      fieldId: this.ctx.fieldId,
      author: { uid: "", displayName: "" },
      nowMs: this.deps.now(),
    });
  }

  private robots(): Robot[] {
    if (!this.practice) return this.ctx.robots;
    const { red, blue } = boardSides(this.board.session);
    return [
      ...red.map((team) => ({ team, side: "red" as const })),
      ...blue.map((team) => ({ team, side: "blue" as const })),
    ];
  }

  private pending(): boolean {
    return this.touched && this.board.session.updatedMs > this.queuedMs;
  }

  private unsent(): boolean {
    return this.pending() || this.deps.unsent(this.board.session.id);
  }

  private resolve() {
    if (this.started || !this.loaded) return;
    if (!this.remoteReady && !this.waited) return;
    this.started = true;
    const record = this.record;
    const mine = record
      ? parseSession(String(record.doc.id ?? ""), record.doc, this.ctx.fieldId)
      : null;
    const theirs = this.remote;
    if (mine && record) {
      this.board = { session: mine, history: emptyHistory() };
      this.queuedMs = record.queuedMs;
      this.touched = true;
      if (theirs && theirs.updatedMs > mine.updatedMs) {
        if (this.unsent()) this.conflict = theirs;
        else this.adopt(theirs);
      }
    } else if (theirs) {
      this.adopt(theirs);
    }
    this.ready = true;
    if (this.pending() && !this.conflict) this.schedule(0);
    this.emit();
  }

  private reconcile() {
    const theirs = this.remote;
    if (!theirs) return;
    if (!this.touched) {
      if (!this.drawing) this.adopt(theirs);
      return;
    }
    const decision = decideRemote({
      mine: this.board.session.updatedMs,
      theirs: theirs.updatedMs,
      unsent: this.unsent(),
      drawing: this.drawing,
    });
    if (decision === "adopt") this.adopt(theirs);
    if (decision === "conflict") this.conflict = theirs;
  }

  private adopt(session: Session) {
    this.clearTimer();
    this.deps.discard(this.board.session.id);
    this.board = { session, history: emptyHistory() };
    this.queuedMs = session.updatedMs;
    this.touched = true;
    this.conflict = null;
    this.persist();
    this.emit();
  }

  private commit(next: Board) {
    this.board = next;
    this.touched = true;
    this.persist();
    if (!this.conflict) this.schedule(this.deps.debounceMs);
    this.emit();
  }

  private forSave(): Session {
    return {
      ...this.board.session,
      selectedPhase: this.phase,
      selectedTool: this.tool,
      selectedRobotTeam: this.state().team,
    };
  }

  private persist() {
    const record: LocalRecord = {
      doc: sessionJson(this.forSave()),
      queuedMs: this.queuedMs,
    };
    this.inFlight++;
    this.chain = this.chain
      .then(() => this.deps.save(record))
      .then(
        () => {
          this.lastSaveOk = true;
        },
        () => {
          this.lastSaveOk = false;
        },
      )
      .then(() => {
        this.inFlight--;
        this.emit();
      });
  }

  private schedule(delay: number) {
    this.clearTimer();
    this.timer = setTimeout(() => this.handoff(), delay);
  }

  private clearTimer() {
    if (this.timer !== null) clearTimeout(this.timer);
    this.timer = null;
  }

  private handoff() {
    this.clearTimer();
    const session = this.board.session;
    if (this.conflict || !this.pending()) return;
    if (session.authorUid === "" && this.author.uid === "") return;
    const doc = sessionDoc(this.forSave(), this.author);
    const before = this.queuedMs;
    this.queuedMs = session.updatedMs;
    this.board = {
      ...this.board,
      session: {
        ...session,
        authorUid: String(doc.authorUid),
        authorDisplayName: String(doc.authorDisplayName),
      },
    };
    this.persist();
    this.deps.enqueue(doc).catch(() => {
      this.queuedMs = before;
      this.emit();
    });
    this.emit();
  }

  private state(): BoardState {
    const s = this.board.session;
    const placed = teamsPlaced(s, this.phase);
    const robots = this.robots();
    const free = robots.find((r) => !placed.has(r.team))?.team ?? null;
    const chosen =
      this.team !== null &&
      !placed.has(this.team) &&
      robots.some((r) => r.team === this.team)
        ? this.team
        : free;
    return {
      ready: this.ready,
      session: s,
      robots,
      practice: this.practice,
      phase: this.phase,
      tool: this.tool,
      team: chosen,
      canUndo: canUndo(this.board.history, this.phase),
      canRedo: canRedo(this.board.history, this.phase),
      local:
        this.inFlight > 0 ? "saving" : this.lastSaveOk ? "saved" : "failed",
      handed: s.updatedMs <= this.queuedMs,
      hasBoard: this.touched,
      remote:
        this.remote === null ? "none" : this.remoteCache ? "cache" : "server",
      conflict: this.conflict,
    };
  }

  private emit() {
    this.snapshot = this.state();
    for (const listener of this.listeners) listener();
  }
}
