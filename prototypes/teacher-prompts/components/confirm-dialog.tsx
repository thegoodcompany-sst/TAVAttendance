"use client";
import { useEffect, useId, useRef } from "react";
import { s } from "@/lib/strings";
export function ConfirmDialog({
  title,
  children,
  confirmLabel = s.confirm,
  pending,
  onConfirm,
  onCancel,
}: {
  title: string;
  children?: React.ReactNode;
  confirmLabel?: string;
  pending: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const confirm = useRef<HTMLButtonElement>(null);
  const titleId = useId();
  useEffect(() => {
    const opener =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    const element = dialog.current!;
    element.showModal();
    confirm.current?.focus();
    return () => {
      element.close();
      opener?.focus();
    };
  }, []);
  return (
    <dialog
      ref={dialog}
      className="confirm-sheet"
      aria-labelledby={titleId}
      onKeyDown={(event) => {
        if (event.key !== "Tab") return;
        const buttons = Array.from(
          dialog.current!.querySelectorAll<HTMLButtonElement>(
            "button:not(:disabled)",
          ),
        );
        const first = buttons[0],
          last = buttons.at(-1);
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault();
          last?.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first?.focus();
        }
      }}
      onCancel={(event) => {
        event.preventDefault();
        if (!pending) onCancel();
      }}
    >
      <div className="stack">
        <h2 id={titleId}>{title}</h2>
        {children}
        <button ref={confirm} disabled={pending} onClick={onConfirm}>
          {confirmLabel}
        </button>
        <button className="quiet" disabled={pending} onClick={onCancel}>
          {s.cancel}
        </button>
      </div>
    </dialog>
  );
}
