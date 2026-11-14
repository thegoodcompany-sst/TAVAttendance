import { s } from "./strings";
export function time(value: string) {
  return new Intl.DateTimeFormat(s.locale, {
    timeZone: s.timezone,
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(value));
}
export function day(value: string) {
  return new Intl.DateTimeFormat(s.locale, {
    timeZone: s.timezone,
    weekday: "short",
    day: "numeric",
    month: "short",
  }).format(new Date(value));
}
export function singaporeDate(date = new Date()) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: s.timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}
export function localInput(value: string) {
  return new Date(new Date(value).getTime() + 8 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 16);
}
