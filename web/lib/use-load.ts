"use client";

import { useCallback, useEffect, useState } from "react";
import { isApiError } from "./api";

interface LoadState<T> {
  loader: (() => Promise<T>) | null;
  data: T | undefined;
  error: string | null;
  status: number | null;
}

async function settle<T>(loader: () => Promise<T>): Promise<LoadState<T>> {
  try {
    return { loader, data: await loader(), error: null, status: null };
  } catch (err) {
    return {
      loader,
      data: undefined,
      error: isApiError(err) ? err.message : "Something went wrong.",
      status: isApiError(err) ? err.status : null,
    };
  }
}

/**
 * Runs `loader` (memoise it with useCallback) and tracks its result. Pass null to
 * skip loading (e.g. while signed out). Results are keyed to the loader identity,
 * so a new loader shows as loading without resetting state inside the effect.
 */
export function useLoad<T>(loader: (() => Promise<T>) | null) {
  const [state, setState] = useState<LoadState<T>>({ loader: null, data: undefined, error: null, status: null });

  useEffect(() => {
    if (!loader) return;
    let current = true;
    settle(loader).then((next) => {
      if (current) setState(next);
    });
    return () => {
      current = false;
    };
  }, [loader]);

  const loading = loader !== null && state.loader !== loader;
  const fresh = state.loader === loader;
  const setData = useCallback(
    (update: (prev: T | undefined) => T) => setState((s) => ({ ...s, data: update(s.data) })),
    [],
  );
  const reload = useCallback(async () => {
    if (loader) setState(await settle(loader));
  }, [loader]);

  return {
    data: fresh ? state.data : undefined,
    error: fresh ? state.error : null,
    status: fresh ? state.status : null,
    loading,
    setData,
    reload,
  };
}
