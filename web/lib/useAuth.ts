"use client";

import { useState, useEffect, useCallback } from "react";
import { auth, googleProvider, signInWithPopup, onAuthStateChanged, type User } from "./firebase";

export function useAuth() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [token, setToken] = useState<string | null>(null);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (user) => {
      setUser(user);
      if (user) {
        const t = await user.getIdToken();
        setToken(t);
      } else {
        setToken(null);
      }
      setLoading(false);
    });
    return unsubscribe;
  }, []);

  // Refresh token periodically (Firebase tokens expire after 1 hour)
  useEffect(() => {
    if (!user) return;
    const interval = setInterval(async () => {
      const t = await user.getIdToken(true);
      setToken(t);
    }, 50 * 60 * 1000); // refresh every 50 minutes
    return () => clearInterval(interval);
  }, [user]);

  const signIn = useCallback(async () => {
    await signInWithPopup(auth, googleProvider);
  }, []);

  const signOut = useCallback(async () => {
    await auth.signOut();
  }, []);

  return { user, loading, token, signIn, signOut };
}
