import type { ApiClient } from "./api";
import { mediaUrl } from "./config";
import { paragraphs } from "./content";
import type { Card, Post } from "./types";

/*
 * Listen mode: the cards read aloud one after another, like the swipe feed but audio only.
 *
 * One app-wide player (see lib/listen.tsx) owns a single <audio> element that plays the chime and
 * every card's recording in turn (iOS only lets an element that a tap has started keep playing in
 * the background, so the element is never swapped), plus a few preloading elements that warm the
 * cache for the next cards. Cards without a recording are read by the browser's own voice
 * (speechSynthesis) so the stream never stops; when even that is impossible they are skipped.
 */

export const SPEEDS = [0.8, 1, 1.25, 1.5] as const;
export const SLEEP_MINUTES = [15, 30, 60] as const;
/** "Previous" restarts the current card once it is more than this far in. */
export const RESTART_AFTER_S = 3;
/** Skipping a card within its first seconds marks nothing. */
export const SKIP_GRACE_S = 5;
/** Hearing this much of a card (or reaching its end) marks it seen and read. */
export const HEARD_RATIO = 0.7;
/** Load the next timeline page when this many cards or fewer are left after the current one. */
export const LOAD_MORE_WHEN_LEFT = 3;
/** How many upcoming cards' recordings are fetched ahead, for short losses of signal. */
export const PREFETCH_AHEAD = 3;
export const SEEK_STEP_S = 10;
export const PAGE_SIZE = 20;
export const CHIME_URL = "/audio/chime.mp3";
/**
 * The optional background music: Chopin's Nocturne Op. 9 No. 2, Musopen's CC0 recording (see
 * content/audio/README.md), mixed about 17 dB under the voices in the file itself, since iOS
 * ignores an element's volume.
 */
export const MUSIC_URL = "/audio/listen-music.mp3";
/** The app icon, for the lock screen and the system media controls. */
export const ARTWORK: MediaImage[] = [{ src: "/listen-artwork.png", sizes: "512x512", type: "image/png" }];

const SPEED_KEY = "reborn.listen.speed";
const MUSIC_KEY = "reborn.listen.music";
/** Speaking pace of the device voice at 1x, to estimate how long a card takes. */
const WORDS_PER_SECOND = 2.6;
/** Device voices cut long utterances short in some browsers: speak at most this much at a time. */
const MAX_CHUNK = 220;
const TICK_MS = 250;

export interface ListenItem {
  /** The post id (the same as the card id). */
  id: string;
  card: Card;
}

export type SleepTimer = { kind: "minutes"; minutes: number; endsAt: number } | { kind: "card" } | null;

/**
 * idle: no session. chime: the short sound between cards. card: a card is current (playing or
 * paused). waiting: the queue ran out and the next page is loading. finished: nothing left.
 */
export type ListenPhase = "idle" | "chime" | "card" | "waiting" | "finished";

export interface ListenState {
  active: boolean;
  items: ListenItem[];
  index: number;
  /** The reader wants it playing (false while paused). */
  playing: boolean;
  phase: ListenPhase;
  /** The card's own recording, or the device voice reading it. */
  voice: "recording" | "device";
  /** Seconds into the current card, and its length (estimated for the device voice). */
  position: number;
  duration: number;
  speed: number;
  /** Background music under the voice while playing (off unless the reader turns it on). */
  music: boolean;
  sleep: SleepTimer;
  /** Only the one card (from its page), no queue. */
  single: boolean;
  /**
   * What a fixed list was started from (e.g. "source:meditations", "author:Epictetus"), so its
   * page can show the session as its own; null for the timeline and single cards.
   */
  queue: string | null;
  loadingMore: boolean;
  error: string | null;
  /** Which session this is: a new number each time one starts. */
  session: number;
}

export type Outcome = "read" | "seen" | "none";

// --- Rules ---------------------------------------------------------------------------------------

/** What "previous" does: restart the current card if more than 3 s in, else go to the card before. */
export function previousAction(position: number, index: number): "restart" | "previous" {
  return position > RESTART_AFTER_S || index <= 0 ? "restart" : "previous";
}

/**
 * What hearing a card counts as: read (and seen) at 70% or at its end; seen only when skipped after
 * the first 5 s; nothing when skipped within them.
 */
export function heardOutcome(heard: number, duration: number, ended: boolean): Outcome {
  if (ended) return "read";
  if (duration > 0 && heard / duration >= HEARD_RATIO) return "read";
  if (heard >= SKIP_GRACE_S) return "seen";
  return "none";
}

/** True when the next page should load: 3 or fewer cards left after the current one. */
export function shouldLoadMore(count: number, index: number, hasMore: boolean): boolean {
  return hasMore && count - 1 - index <= LOAD_MORE_WHEN_LEFT;
}

/** The card's recording, resolved like explainer URLs (relative to the API base), or null. */
export function audioUrl(card: Card): string | null {
  return card.audio?.url ? mediaUrl(card.audio.url) : null;
}

export function authorsText(authors: string[]): string {
  if (authors.length <= 1) return authors[0] ?? "";
  return `${authors.slice(0, -1).join(", ")} and ${authors[authors.length - 1]}`;
}

/** "Source title · Author", for the player and the lock screen. */
export function sourceLine(card: Card): string {
  if (card.author) return `by ${card.author.display_name}`;
  const by = authorsText(card.source.authors);
  return by ? `${card.source.title} · ${by}` : card.source.title;
}

/**
 * What the device voice reads, the same script as the recordings: the title, the body, "Apply it."
 * and the step, the health or support note when there is one, then the credit.
 */
export function listenText(card: Card): string {
  const by = authorsText(card.source.authors);
  return [
    card.title,
    ...paragraphs(card.body),
    card.apply_it?.trim() ? `Apply it. ${card.apply_it}` : "",
    card.disclaimer ?? "",
    card.author
      ? `By ${card.author.display_name}.`
      : by
        ? `From ${card.source.title}, by ${by}.`
        : `From ${card.source.title}.`,
  ]
    .map((p) => p.trim())
    .filter(Boolean)
    .join("\n\n");
}

/** About how long the device voice takes to read `text` at 1x, in seconds. */
export function estimateSeconds(text: string): number {
  const words = text.split(/\s+/).filter(Boolean).length;
  return Math.max(1, words / WORDS_PER_SECOND);
}

/** The text cut into paragraphs and, where long, sentences: {start offset, text}. */
export function speechChunks(text: string): { start: number; text: string }[] {
  const out: { start: number; text: string }[] = [];
  const re = /[^\n]+/g;
  for (let m = re.exec(text); m; m = re.exec(text)) {
    let start = m.index;
    let rest = m[0];
    while (rest.length > MAX_CHUNK) {
      const cut = Math.max(rest.lastIndexOf(". ", MAX_CHUNK), rest.lastIndexOf(", ", MAX_CHUNK), rest.lastIndexOf(" ", MAX_CHUNK));
      const at = cut > 0 ? cut + 1 : MAX_CHUNK;
      out.push({ start, text: rest.slice(0, at).trim() });
      start += at;
      rest = rest.slice(at);
    }
    if (rest.trim()) out.push({ start, text: rest.trim() });
  }
  return out;
}

/** 0:42, 1:05:09. */
export function formatTime(s: number): string {
  const t = Math.max(0, Math.floor(Number.isFinite(s) ? s : 0));
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const sec = String(t % 60).padStart(2, "0");
  return h ? `${h}:${String(m).padStart(2, "0")}:${sec}` : `${m}:${sec}`;
}

export function readSpeed(): number {
  try {
    const v = Number(window.localStorage.getItem(SPEED_KEY));
    return (SPEEDS as readonly number[]).includes(v) ? v : 1;
  } catch {
    return 1;
  }
}

export function readMusic(): boolean {
  try {
    return window.localStorage.getItem(MUSIC_KEY) === "1";
  } catch {
    return false;
  }
}

function saveMusic(on: boolean) {
  try {
    window.localStorage.setItem(MUSIC_KEY, on ? "1" : "0");
  } catch {
    // Storage unavailable: the choice lasts for this visit only.
  }
}

function saveSpeed(v: number) {
  try {
    window.localStorage.setItem(SPEED_KEY, String(v));
  } catch {
    // Storage unavailable (private mode): the speed lasts for this visit only.
  }
}

export function itemsFromPosts(posts: Post[]): ListenItem[] {
  return posts.map((p) => ({ id: p.id, card: p.card }));
}

/** A card's post has the card's id. */
export function itemsFromCards(cards: Card[]): ListenItem[] {
  return cards.map((card) => ({ id: card.id, card }));
}

// --- The player ----------------------------------------------------------------------------------

export interface ListenDeps {
  api: Pick<ApiClient, "timeline" | "markSeen" | "recordView">;
  /** Seen and read are only recorded for signed-in readers. */
  signedIn: () => boolean;
  createAudio?: () => HTMLAudioElement;
  speech?: () => SpeechSynthesis | null;
  createUtterance?: (text: string) => SpeechSynthesisUtterance;
  mediaSession?: () => MediaSession | null;
  now?: () => number;
}

export interface StartOptions {
  items: ListenItem[];
  index?: number;
  /** Where the timeline continues (null: nothing more). */
  cursor?: string | null;
  /** The feed's topic filter, as `topics` for /v1/timeline. */
  topics?: string;
  /** The feed's media filter, as `media` for /v1/timeline. */
  media?: "video" | "image";
  single?: boolean;
  /** Names a fixed list (see ListenState.queue). */
  queue?: string;
  /** Start paused rather than playing (the session follows the page while paused). */
  paused?: boolean;
}

/** What a page plays, for Listen mode to follow when the reader moves to it (see `follow`). */
export interface FollowTarget {
  items: ListenItem[];
  /**
   * The item on screen, followed as the reader moves through the page. Without one (a book's list)
   * the list starts from its first item, and opening the page again leaves its session alone.
   */
  index?: number;
  /** Names the page's list, e.g. "source:meditations|all", "summary:x", "timeline|". */
  queue: string;
  cursor?: string | null;
  topics?: string;
  media?: "video" | "image";
}

const IDLE: Omit<ListenState, "speed" | "music"> = {
  active: false,
  items: [],
  index: 0,
  playing: false,
  phase: "idle",
  voice: "recording",
  position: 0,
  duration: 0,
  sleep: null,
  single: false,
  queue: null,
  loadingMore: false,
  error: null,
  session: 0,
};

const MEDIA_ACTIONS: MediaSessionAction[] = [
  "play",
  "pause",
  "stop",
  "nexttrack",
  "previoustrack",
  "seekbackward",
  "seekforward",
  "seekto",
];

export class ListenPlayer {
  private state: ListenState = { ...IDLE, speed: 1, music: false };
  private listeners = new Set<() => void>();
  private deps: Required<ListenDeps>;
  private audio: HTMLAudioElement | null = null;
  private musicEl: HTMLAudioElement | null = null;
  private preloads = new Map<string, HTMLAudioElement>();
  private cursor: string | null = null;
  private topics = "";
  private media: "video" | "image" | undefined;
  /** Bumped whenever the session restarts, so late timeline pages are dropped. */
  private session = 0;
  private speedLoaded = false;
  // The current card.
  private heard = 0;
  private lastPos = 0;
  private marks = new Map<string, "seen" | "read">();
  private ignorePauseUntil = 0;
  // The device voice.
  private speechGen = 0;
  private chunks: { start: number; text: string }[] = [];
  private textLength = 1;
  private chunkIndex = 0;
  private chunkStartedAt = 0;
  private chunkStartPos = 0;
  private tick: ReturnType<typeof setInterval> | undefined;
  private sleepTimer: ReturnType<typeof setTimeout> | undefined;
  private mediaBound = false;

  constructor(deps: ListenDeps) {
    this.deps = {
      createAudio: () => new Audio(),
      speech: () => (typeof window !== "undefined" && "speechSynthesis" in window ? window.speechSynthesis : null),
      createUtterance: (text) => new SpeechSynthesisUtterance(text),
      mediaSession: () => (typeof navigator !== "undefined" && "mediaSession" in navigator ? navigator.mediaSession : null),
      now: () => Date.now(),
      ...deps,
    };
  }

  // Store (for useSyncExternalStore).
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  getState = (): ListenState => this.state;

  private set(patch: Partial<ListenState>) {
    this.state = { ...this.state, ...patch };
    this.syncMediaSession();
    this.syncMusic();
    this.listeners.forEach((l) => l());
  }

  get current(): ListenItem | null {
    return this.state.active ? (this.state.items[this.state.index] ?? null) : null;
  }

  /** Can this card be listened to at all here (a recording, or a device voice)? */
  canPlay(card: Card): boolean {
    return !!audioUrl(card) || !!this.deps.speech();
  }

  // --- Commands ------------------------------------------------------------------------------------

  /** Starts a session. Call it straight from the tap, so the browser allows sound. */
  start(opts: StartOptions, keepSleep = false) {
    if (this.state.active) this.leave(false);
    const sleep = keepSleep ? this.state.sleep : null;
    this.teardown(keepSleep);
    if (!this.speedLoaded) {
      this.speedLoaded = true;
      this.state = { ...this.state, speed: readSpeed(), music: readMusic() };
    }
    this.session++;
    this.cursor = opts.single ? null : (opts.cursor ?? null);
    this.topics = opts.topics ?? "";
    this.media = opts.media;
    const items = opts.items.filter((i, n, all) => all.findIndex((o) => o.id === i.id) === n);
    if (!items.length) return;
    this.set({
      ...IDLE,
      speed: this.state.speed,
      music: this.state.music,
      active: true,
      items,
      index: Math.min(Math.max(0, opts.index ?? 0), items.length - 1),
      playing: !opts.paused,
      single: !!opts.single,
      queue: opts.queue ?? null,
      sleep,
      session: this.session,
    });
    this.bindMediaSession();
    this.go(this.state.index, false);
  }

  /**
   * Starts a session over a fixed list of cards, in order (a book's or an author's page): no
   * timeline paging, so it finishes after the last card. Seen and read work as in the timeline.
   */
  playCards(cards: Card[], opts: { queue?: string; index?: number } = {}) {
    this.start({ items: itemsFromCards(cards), index: opts.index, cursor: null, queue: opts.queue });
  }

  /**
   * The reader moved to a page with audio of its own while a session is on: the session switches to
   * that page's audio, carrying on from the item on screen and keeping play or pause (and the sleep
   * timer). Already on that page's list: moves to the item on screen if it isn't the current one.
   * Does nothing when no session is on.
   */
  follow(target: FollowTarget) {
    const { active, queue, items, index, playing } = this.state;
    if (!active || !target.items.length) return;
    if (queue === target.queue) {
      const want = target.items[target.index ?? -1];
      if (!want) return;
      const at = items.findIndex((i) => i.id === want.id);
      if (at === index) return;
      if (at >= 0) return this.jump(at);
    }
    this.start(
      {
        items: target.items,
        index: target.index ?? 0,
        cursor: target.cursor ?? null,
        topics: target.topics,
        media: target.media,
        queue: target.queue,
        paused: !playing,
      },
      true,
    );
  }

  /**
   * The reader opened a card's own page while a session is on: its card becomes the current one,
   * within the session when the card is in it (so it carries on after), else on its own.
   */
  followCard(card: Card) {
    const { active, items, index, playing } = this.state;
    if (!active) return;
    const at = items.findIndex((i) => i.id === card.id);
    if (at === index) return;
    if (at >= 0) return this.jump(at);
    this.start({ items: [{ id: card.id, card }], single: true, paused: !playing }, true);
  }

  /** Moves to item `index` of this session, keeping play or pause. */
  private jump(index: number) {
    if (this.state.phase === "waiting") return;
    this.leave(false);
    this.go(index, false);
  }

  play() {
    if (!this.state.active) return;
    const { phase } = this.state;
    if (phase === "finished" || phase === "waiting") return;
    this.set({ playing: true });
    if (phase === "chime" || this.state.voice === "recording") this.playAudio();
    else this.speakFrom(this.state.position);
  }

  pause() {
    if (!this.state.active || !this.state.playing) return;
    this.audio?.pause();
    if (this.state.voice === "device") this.cancelSpeech();
    this.set({ playing: false });
  }

  toggle() {
    if (this.state.playing) this.pause();
    else this.play();
  }

  next() {
    if (!this.state.active || this.state.phase === "waiting") return;
    this.leave(false);
    this.advance(false);
  }

  previous() {
    if (!this.state.active) return;
    if (previousAction(this.state.position, this.state.index) === "restart" || this.state.phase === "chime") {
      if (this.state.phase === "chime") this.beginCard();
      else this.seek(0);
      return;
    }
    this.leave(false);
    this.go(this.state.index - 1, false);
  }

  /** Jumps to `seconds` into the current card. Jumps don't count as heard. */
  seek(seconds: number) {
    if (!this.state.active || this.state.phase !== "card") return;
    const max = this.state.duration > 0 ? this.state.duration : Infinity;
    const t = Math.min(Math.max(0, seconds), max);
    this.lastPos = t;
    if (this.state.voice === "recording") {
      if (this.audio) this.audio.currentTime = t;
      this.set({ position: t });
    } else {
      this.set({ position: t });
      if (this.state.playing) this.speakFrom(t);
    }
  }

  back() {
    this.seek(this.state.position - SEEK_STEP_S);
  }

  setSpeed(speed: number) {
    if (!(SPEEDS as readonly number[]).includes(speed)) return;
    saveSpeed(speed);
    this.speedLoaded = true;
    if (this.audio && this.state.phase === "card") {
      this.audio.playbackRate = speed;
      this.audio.defaultPlaybackRate = speed;
    }
    this.set({ speed });
    if (this.state.active && this.state.voice === "device" && this.state.playing && this.state.phase === "card") {
      this.speakFrom(this.state.position);
    }
  }

  /** Background music on or off (remembered on this device). Call it from the tap, for iOS. */
  setMusic(on: boolean) {
    saveMusic(on);
    this.set({ music: on });
  }

  /** The music plays exactly while a session is playing with music on. */
  private syncMusic() {
    const { active, playing, music, phase } = this.state;
    const want = active && playing && music && phase !== "finished";
    if (!want) {
      if (this.musicEl && !this.musicEl.paused) this.musicEl.pause();
      return;
    }
    if (!this.musicEl) {
      const el = this.deps.createAudio();
      el.preload = "none";
      el.loop = true;
      el.src = MUSIC_URL;
      this.musicEl = el;
    }
    if (this.musicEl.paused) {
      this.musicEl.play()?.catch(() => {
        // Blocked or unavailable: the voice carries on without it.
      });
    }
  }

  /** A sleep timer: 15, 30 or 60 minutes, the end of this card ("card"), or off (null). */
  setSleep(option: number | "card" | null) {
    clearTimeout(this.sleepTimer);
    this.sleepTimer = undefined;
    if (option === "card") return this.set({ sleep: { kind: "card" } });
    if (typeof option !== "number") return this.set({ sleep: null });
    const ms = option * 60_000;
    this.sleepTimer = setTimeout(() => {
      this.sleepTimer = undefined;
      this.pause();
      this.set({ sleep: null });
    }, ms);
    this.set({ sleep: { kind: "minutes", minutes: option, endsAt: this.deps.now() + ms } });
  }

  /** Ends the session and hides the player. */
  stop() {
    if (!this.state.active) return;
    this.leave(false);
    this.teardown();
    this.session++;
    this.set({ ...IDLE, speed: this.state.speed, music: this.state.music, session: this.session });
    this.unbindMediaSession();
  }

  // --- Moving through the queue ------------------------------------------------------------------

  private go(index: number, chime: boolean) {
    const item = this.state.items[index];
    if (!item) return;
    this.cancelSpeech();
    this.stopTick();
    this.heard = 0;
    this.lastPos = 0;
    const url = audioUrl(item.card);
    const text = url ? "" : listenText(item.card);
    this.chunks = text ? speechChunks(text) : [];
    this.textLength = Math.max(1, text.length);
    const duration = url ? (item.card.audio?.duration_s ?? 0) : estimateSeconds(text);
    this.set({ index, position: 0, duration, voice: url ? "recording" : "device", error: null });
    this.prefetch();
    this.maybeLoadMore();
    if (chime && this.state.playing) {
      this.set({ phase: "chime" });
      this.setSrc(CHIME_URL, 1);
      this.playAudio();
    } else {
      this.beginCard();
    }
  }

  private beginCard() {
    const item = this.current;
    if (!item) return;
    const url = audioUrl(item.card);
    this.set({ phase: "card" });
    if (url) {
      this.set({ voice: "recording" });
      this.setSrc(url, this.state.speed);
      if (this.state.playing) this.playAudio();
      return;
    }
    if (!this.deps.speech()) {
      // Nothing can read it here: skip it so the stream carries on.
      this.advance(false);
      return;
    }
    if (this.audio) {
      this.ignorePauseUntil = this.deps.now() + 500;
      this.audio.pause();
    }
    this.set({ voice: "device" });
    if (this.state.playing) this.speakFrom(0);
  }

  /** The current card finished playing. */
  private cardEnded() {
    this.stopTick();
    this.set({ position: this.state.duration });
    this.leave(true);
    if (this.state.sleep?.kind === "card") {
      // Sleep at the end of this card: line up the next one, paused.
      this.set({ sleep: null, playing: false });
      this.audio?.pause();
    }
    this.advance(this.state.playing);
  }

  private advance(chime: boolean) {
    const { index, items } = this.state;
    if (index + 1 < items.length) return this.go(index + 1, chime);
    if (this.cursor && !this.state.single) {
      this.audio?.pause();
      this.cancelSpeech();
      this.stopTick();
      this.set({ phase: "waiting" });
      void this.loadMore();
      return;
    }
    this.finish();
  }

  private finish() {
    this.audio?.pause();
    this.cancelSpeech();
    this.stopTick();
    this.set({ phase: "finished", playing: false });
  }

  private maybeLoadMore() {
    const { items, index, single } = this.state;
    if (!single && shouldLoadMore(items.length, index, !!this.cursor)) void this.loadMore();
  }

  private loading = false;

  private async loadMore() {
    if (this.loading || !this.cursor) return;
    this.loading = true;
    const session = this.session;
    let handedOff = false;
    this.set({ loadingMore: true });
    try {
      // Keep going while pages come back with nothing new and the queue is waiting on them.
      while (this.cursor) {
        const page = await this.deps.api.timeline(
          { cursor: this.cursor, limit: PAGE_SIZE, topics: this.topics || undefined, media: this.media },
          this.deps.signedIn(),
        );
        if (session !== this.session) return;
        this.cursor = page.next_cursor;
        const have = new Set(this.state.items.map((i) => i.id));
        const fresh = itemsFromPosts(page.posts).filter((i) => !have.has(i.id));
        if (fresh.length) this.set({ items: [...this.state.items, ...fresh] });
        if (this.state.phase !== "waiting") break;
        if (fresh.length) {
          handedOff = true;
          this.loading = false;
          this.set({ loadingMore: false });
          this.go(this.state.index + 1, false);
          return;
        }
      }
      this.set({ loadingMore: false });
      this.prefetch();
      if (this.state.phase === "waiting") this.finish();
    } catch {
      if (session !== this.session) return;
      this.set({ loadingMore: false, error: "Couldn't load more ideas." });
      if (this.state.phase === "waiting") this.finish();
    } finally {
      if (session === this.session && !handedOff) this.loading = false;
    }
  }

  // --- Seen and read -------------------------------------------------------------------------------

  /** Leaving the current card (it ended, or the reader moved on): record what it counted as. */
  private leave(ended: boolean) {
    const item = this.current;
    if (!item || this.state.phase === "waiting" || this.state.phase === "finished") return;
    if (this.state.phase === "chime") return;
    this.record(item.id, heardOutcome(this.heard, this.state.duration, ended));
  }

  private record(id: string, outcome: Outcome) {
    if (outcome === "none" || !this.deps.signedIn()) return;
    const before = this.marks.get(id);
    if (before === "read" || before === outcome) return;
    this.marks.set(id, outcome);
    if (!before) {
      this.deps.api.markSeen([id]).catch(() => {
        if (this.marks.get(id) === "seen") this.marks.delete(id);
      });
    }
    if (outcome === "read") {
      this.deps.api.recordView(id).catch(() => this.marks.set(id, "seen"));
    }
  }

  /** Playback moved on to `pos`: count it as heard unless it jumped. */
  private progress(pos: number) {
    const delta = pos - this.lastPos;
    if (delta > 0 && delta <= 2 * this.state.speed + 1) this.heard += delta;
    this.lastPos = pos;
    this.set({ position: pos });
    const item = this.current;
    if (item && heardOutcome(this.heard, this.state.duration, false) === "read") this.record(item.id, "read");
  }

  // --- The audio element -------------------------------------------------------------------------

  private ensureAudio(): HTMLAudioElement {
    if (this.audio) return this.audio;
    const a = this.deps.createAudio();
    a.preload = "auto";
    a.addEventListener("timeupdate", () => {
      if (this.state.phase === "card" && this.state.voice === "recording") this.progress(a.currentTime);
    });
    a.addEventListener("loadedmetadata", () => {
      if (this.state.phase === "card" && this.state.voice === "recording" && Number.isFinite(a.duration) && a.duration > 0) {
        this.set({ duration: a.duration });
      }
    });
    a.addEventListener("ended", () => {
      if (this.state.phase === "chime") this.beginCard();
      else if (this.state.phase === "card" && this.state.voice === "recording") this.cardEnded();
    });
    a.addEventListener("error", () => this.audioFailed());
    // Paused or resumed from outside (a call, headphones unplugged, the system's own controls).
    a.addEventListener("pause", () => {
      if (a.ended || this.deps.now() < this.ignorePauseUntil) return;
      if (this.state.playing && (this.state.phase === "card" || this.state.phase === "chime") && this.state.voice === "recording") {
        this.set({ playing: false });
      }
    });
    a.addEventListener("play", () => {
      if (this.state.active && !this.state.playing && this.state.phase === "card") this.set({ playing: true });
    });
    this.audio = a;
    return a;
  }

  private setSrc(url: string, rate: number) {
    const a = this.ensureAudio();
    this.ignorePauseUntil = this.deps.now() + 500;
    a.src = url;
    a.defaultPlaybackRate = rate;
    a.playbackRate = rate;
  }

  private playAudio() {
    const a = this.ensureAudio();
    let p: Promise<void> | undefined;
    try {
      p = a.play();
    } catch (err) {
      p = Promise.reject(err);
    }
    Promise.resolve(p).catch((err: { name?: string }) => {
      if (err?.name === "AbortError") return; // a newer src replaced it
      if (err?.name === "NotAllowedError") {
        // The browser wants a tap first: wait paused for one.
        this.set({ playing: false });
        return;
      }
      this.audioFailed();
    });
  }

  /** The chime or a recording couldn't play: carry on with the card, read by the device voice. */
  private audioFailed() {
    if (!this.state.active) return;
    if (this.state.phase === "chime") return this.beginCard();
    if (this.state.phase !== "card" || this.state.voice !== "recording") return;
    const item = this.current;
    if (!item) return;
    if (!this.deps.speech()) return this.advance(false);
    const text = listenText(item.card);
    this.chunks = speechChunks(text);
    this.textLength = Math.max(1, text.length);
    this.heard = 0;
    this.lastPos = 0;
    this.set({ voice: "device", position: 0, duration: estimateSeconds(text) });
    if (this.state.playing) this.speakFrom(0);
  }

  /** Warms the cache with the next cards' recordings. */
  private prefetch() {
    const { items, index } = this.state;
    const want = new Set(
      items
        .slice(index + 1, index + 1 + PREFETCH_AHEAD)
        .map((i) => audioUrl(i.card))
        .filter((u): u is string => !!u),
    );
    for (const [url, el] of this.preloads) {
      if (want.has(url)) continue;
      el.removeAttribute("src");
      this.preloads.delete(url);
    }
    for (const url of want) {
      if (this.preloads.has(url)) continue;
      const el = this.deps.createAudio();
      el.preload = "auto";
      el.muted = true;
      el.src = url;
      this.preloads.set(url, el);
    }
  }

  // --- The device voice ----------------------------------------------------------------------------

  private speakFrom(position: number) {
    const synth = this.deps.speech();
    if (!synth || !this.chunks.length) return;
    this.cancelSpeech();
    const at = (Math.min(position, this.state.duration) / Math.max(this.state.duration, 1)) * this.textLength;
    let i = 0;
    for (let n = 0; n < this.chunks.length; n++) if (this.chunks[n].start <= at) i = n;
    this.lastPos = this.chunkPos(i);
    this.set({ position: this.lastPos });
    this.speakChunk(i, this.speechGen);
  }

  private chunkPos(i: number): number {
    const c = this.chunks[i];
    return c ? (c.start / this.textLength) * this.state.duration : this.state.duration;
  }

  private speakChunk(i: number, gen: number) {
    const synth = this.deps.speech();
    const chunk = this.chunks[i];
    if (!synth || !chunk || gen !== this.speechGen) return;
    const u = this.deps.createUtterance(chunk.text);
    u.lang = "en";
    u.rate = this.state.speed;
    u.onend = () => {
      if (gen !== this.speechGen) return;
      if (i + 1 < this.chunks.length) this.speakChunk(i + 1, gen);
      else this.cardEnded();
    };
    u.onerror = (e) => {
      if (gen !== this.speechGen) return;
      if (e.error === "interrupted" || e.error === "canceled") return;
      // The device voice can't read it after all: skip it.
      this.stopTick();
      this.leave(false);
      this.advance(false);
    };
    this.chunkIndex = i;
    this.chunkStartPos = this.chunkPos(i);
    this.chunkStartedAt = this.deps.now();
    synth.speak(u);
    this.startTick();
  }

  private cancelSpeech() {
    this.speechGen++;
    this.stopTick();
    const synth = this.deps.speech();
    if (synth && (synth.speaking || synth.pending)) synth.cancel();
  }

  private startTick() {
    if (this.tick !== undefined) return;
    this.tick = setInterval(() => {
      if (!this.state.playing || this.state.voice !== "device" || this.state.phase !== "card") return;
      const end = this.chunkPos(this.chunkIndex + 1);
      const elapsed = ((this.deps.now() - this.chunkStartedAt) / 1000) * this.state.speed;
      this.progress(Math.min(end, this.chunkStartPos + elapsed));
    }, TICK_MS);
  }

  private stopTick() {
    clearInterval(this.tick);
    this.tick = undefined;
  }

  // --- Lock screen and headphone controls ----------------------------------------------------------

  private bindMediaSession() {
    const ms = this.deps.mediaSession();
    if (!ms || this.mediaBound) return;
    this.mediaBound = true;
    const handlers: Partial<Record<MediaSessionAction, MediaSessionActionHandler>> = {
      play: () => this.play(),
      pause: () => this.pause(),
      stop: () => this.stop(),
      nexttrack: () => this.next(),
      previoustrack: () => this.previous(),
      seekbackward: (d) => this.seek(this.state.position - (d.seekOffset ?? SEEK_STEP_S)),
      seekforward: (d) => this.seek(this.state.position + (d.seekOffset ?? SEEK_STEP_S)),
      seekto: (d) => {
        if (typeof d.seekTime === "number") this.seek(d.seekTime);
      },
    };
    for (const action of MEDIA_ACTIONS) {
      try {
        ms.setActionHandler(action, handlers[action] ?? null);
      } catch {
        // This browser doesn't know that action.
      }
    }
  }

  private unbindMediaSession() {
    const ms = this.deps.mediaSession();
    if (!ms) return;
    this.mediaBound = false;
    for (const action of MEDIA_ACTIONS) {
      try {
        ms.setActionHandler(action, null);
      } catch {
        // Unknown action.
      }
    }
    try {
      ms.metadata = null;
      ms.playbackState = "none";
    } catch {
      // Read-only in some test environments.
    }
  }

  private shownId: string | null = null;

  private syncMediaSession() {
    if (!this.state.active) return;
    const ms = this.deps.mediaSession();
    if (!ms) return;
    const item = this.current;
    try {
      if (item && item.id !== this.shownId) {
        this.shownId = item.id;
        const init: MediaMetadataInit = {
          title: item.card.title,
          artist: sourceLine(item.card),
          album: "Reborn",
          artwork: ARTWORK,
        };
        ms.metadata = typeof MediaMetadata !== "undefined" ? new MediaMetadata(init) : (init as unknown as MediaMetadata);
      }
      ms.playbackState = this.state.playing ? "playing" : "paused";
      const { duration, position, speed, phase } = this.state;
      if (phase === "card" && duration > 0 && typeof ms.setPositionState === "function") {
        ms.setPositionState({ duration, playbackRate: speed, position: Math.min(position, duration) });
      }
    } catch {
      // Partial Media Session support: the lock screen shows less.
    }
  }

  private teardown(keepSleep = false) {
    this.cancelSpeech();
    this.stopTick();
    if (!keepSleep) {
      clearTimeout(this.sleepTimer);
      this.sleepTimer = undefined;
    }
    this.shownId = null;
    this.loading = false;
    if (this.audio) {
      this.ignorePauseUntil = this.deps.now() + 500;
      this.audio.pause();
      this.audio.removeAttribute("src");
    }
    for (const el of this.preloads.values()) el.removeAttribute("src");
    this.preloads.clear();
  }
}
