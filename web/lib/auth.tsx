"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useSyncExternalStore,
  type ReactNode,
} from "react";
import { createApiClient, isApiError, type ApiClient } from "./api";
import { browserApiUrl } from "./config";
import type { User } from "./types";

const STORAGE_KEY = "reborn.auth";

interface StoredAuth {
  token: string;
  user: User;
}

// --- A tiny external store over localStorage -------------------------------

const listeners = new Set<() => void>();
let cachedRaw: string | null | undefined;
let cachedValue: StoredAuth | null = null;

function readRaw(): string | null {
  try {
    return window.localStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}

function getSnapshot(): StoredAuth | null {
  const raw = readRaw();
  if (raw !== cachedRaw) {
    cachedRaw = raw;
    try {
      const parsed = raw ? (JSON.parse(raw) as StoredAuth) : null;
      cachedValue = parsed && typeof parsed.token === "string" && parsed.user ? parsed : null;
    } catch {
      cachedValue = null;
    }
  }
  return cachedValue;
}

function getServerSnapshot(): StoredAuth | null {
  return null;
}

function emit() {
  listeners.forEach((l) => l());
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  const onStorage = (e: StorageEvent) => {
    if (e.key === STORAGE_KEY || e.key === null) listener();
  };
  window.addEventListener("storage", onStorage);
  return () => {
    listeners.delete(listener);
    window.removeEventListener("storage", onStorage);
  };
}

function write(value: StoredAuth | null) {
  try {
    if (value) window.localStorage.setItem(STORAGE_KEY, JSON.stringify(value));
    else window.localStorage.removeItem(STORAGE_KEY);
  } catch {
    // Storage unavailable (private mode): fall back to in-memory for this tab.
    cachedRaw = value ? JSON.stringify(value) : null;
    cachedValue = value;
  }
  emit();
}

/** Current token, read synchronously (used by the API client). */
export function currentToken(): string | null {
  if (typeof window === "undefined") return null;
  return getSnapshot()?.token ?? null;
}

const noopSubscribe = () => () => {};

/** True once the component has hydrated on the client. */
export function useHydrated(): boolean {
  return useSyncExternalStore(
    noopSubscribe,
    () => true,
    () => false,
  );
}

// --- Context -----------------------------------------------------------------

export interface AuthContextValue {
  /** False until localStorage has been read on the client. */
  ready: boolean;
  token: string | null;
  user: User | null;
  api: ApiClient;
  signIn: (token: string, user: User) => void;
  signOut: () => void;
  setUser: (user: User) => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const stored = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
  const ready = useHydrated();
  const api = useMemo(() => createApiClient(browserApiUrl(), currentToken), []);

  const signIn = useCallback((token: string, user: User) => write({ token, user }), []);
  const signOut = useCallback(() => write(null), []);
  const setUser = useCallback((user: User) => {
    const cur = getSnapshot();
    if (cur) write({ token: cur.token, user });
  }, []);

  // Refresh the profile once per token; drop an expired/invalid token.
  const token = stored?.token ?? null;
  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    api
      .me()
      .then((user) => {
        if (!cancelled) setUser(user);
      })
      .catch((err) => {
        if (!cancelled && isApiError(err) && err.status === 401) signOut();
      });
    return () => {
      cancelled = true;
    };
  }, [api, token, setUser, signOut]);

  const value = useMemo<AuthContextValue>(
    () => ({
      ready,
      token,
      user: stored?.user ?? null,
      api,
      signIn,
      signOut,
      setUser,
    }),
    [ready, token, stored, api, signIn, signOut, setUser],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside <AuthProvider>");
  return ctx;
}
