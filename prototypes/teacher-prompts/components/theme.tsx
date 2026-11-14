"use client";
import { useSyncExternalStore } from "react";
import { s } from "@/lib/strings";
const subscribe = (listener: () => void) => {
  window.addEventListener("tp-theme", listener);
  const media = window.matchMedia("(prefers-color-scheme: dark)");
  media.addEventListener("change", listener);
  return () => {
    window.removeEventListener("tp-theme", listener);
    media.removeEventListener("change", listener);
  };
};
const snapshot = () =>
  localStorage.getItem("tp-theme") ??
  (window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light");
export function Theme() {
  const theme = useSyncExternalStore(subscribe, snapshot, () => "light");
  return (
    <button
      className="quiet theme"
      aria-label={s.theme}
      onClick={() => {
        const next = theme === "dark" ? "light" : "dark";
        localStorage.setItem("tp-theme", next);
        document.documentElement.dataset.theme = next;
        window.dispatchEvent(new Event("tp-theme"));
      }}
    >
      {theme === "dark" ? s.light : s.dark}
    </button>
  );
}
