/** Stand-in copy; Edmund owns final wording. This is the dispatch surface's copy source. */
export const promptStrings = {
  title: "TAVA",
  bodies: {
    heads_up: "Your lesson ends soon.",
    attendance: "Please take attendance.",
    follow_up: "Please review your lesson.",
    final: "Your lesson is waiting for review.",
  },
  methodNotAllowed: "Method not allowed.",
  forbidden: "Not allowed.",
  invalidRequest: "Invalid request.",
  unavailable: "Service unavailable.",
  workerFailed: "Worker failed.",
} as const;
