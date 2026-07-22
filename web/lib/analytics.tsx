'use client'

import { useEffect, useState } from 'react'
import { usePathname } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

type EventType = 'screen_view' | 'tap' | 'error' | 'crash' | 'ops' | 'latency'
type PropertyValue = string | number | boolean | null

type EventInput = {
  eventType: EventType
  name: string
  properties?: Record<string, PropertyValue>
}

type Enqueue = (event: EventInput) => void

let activeEnqueue: Enqueue | null = null

const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/gi

declare global {
  interface Window {
    __tavaNavigationStart?: number
  }
}

function normalisePath(path: string): string {
  return path.replace(UUID, '{id}').replace(/\/\d+(?=\/|$)/g, '/{id}')
}

export function redactAnalyticsText(value: unknown): string {
  // Browser/runtime error messages can echo submitted form values. Analytics
  // needs the failure category, not the potentially personal description.
  if (value instanceof Error) return value.name.slice(0, 80)
  if (value && typeof value === 'object') return value.constructor?.name?.slice(0, 80) || 'Error'
  return value == null ? 'UnknownError' : `${typeof value}Error`
}

export function trackAnalyticsEvent(event: EventInput) {
  activeEnqueue?.(event)
}

export function AnalyticsCapture({
  enabled,
  userId,
  role,
}: {
  enabled: boolean
  userId: string
  role: string
}) {
  const pathname = usePathname()
  const [sessionId] = useState(() => crypto.randomUUID())

  useEffect(() => {
    if (!enabled) return

    const queue: Array<Record<string, unknown>> = []
    const supabase = createClient()
    let draining = false

    const drain = async () => {
      if (draining) return
      draining = true
      try {
        do {
          const batch = queue.splice(0, 100)
          if (batch.length > 0) {
            await supabase.rpc('submit_app_events', { p_events: batch })
          }
        } while (queue.length > 0)
      } catch {
        queue.splice(0)
      } finally {
        draining = false
        if (queue.length > 0) void drain()
      }
    }

    const enqueue: Enqueue = ({ eventType, name, properties = {} }) => {
      queue.push({
        user_id: userId,
        role,
        platform: 'web',
        app_version: process.env.NEXT_PUBLIC_APP_VERSION ?? null,
        session_id: sessionId,
        event_type: eventType,
        name,
        properties,
        device: navigator.platform || null,
      })
    }

    activeEnqueue = enqueue
    enqueue({ eventType: 'ops', name: 'app_launch', properties: { cold: true } })

    const interval = window.setInterval(drain, 15_000)
    const onVisibility = () => {
      if (document.visibilityState === 'hidden') void drain()
    }
    const onClick = (event: MouseEvent) => {
      const element = event.target instanceof Element
        ? event.target.closest<HTMLElement>('[data-analytics],button,a')
        : null
      if (!element) return

      let label = element.dataset.analytics
      if (!label && element instanceof HTMLAnchorElement) {
        label = `route:${normalisePath(new URL(element.href, location.href).pathname)}`
      }
      if (!label && element instanceof HTMLButtonElement) label = `type:${element.type}`
      if (!label) return

      enqueue({
        eventType: 'tap',
        name: `${element.tagName.toLowerCase()}:${label.slice(0, 80)}`,
        properties: { path: normalisePath(location.pathname) },
      })
    }
    const onError = (event: ErrorEvent) => {
      enqueue({
        eventType: 'crash',
        name: 'crash_detected',
        properties: { mechanism: 'window.onerror', reason: redactAnalyticsText(event.error ?? event.message) },
      })
    }
    const onRejection = (event: PromiseRejectionEvent) => {
      enqueue({
        eventType: 'error',
        name: 'unhandled_rejection',
        properties: { message: redactAnalyticsText(event.reason), screen: normalisePath(location.pathname) },
      })
    }

    document.addEventListener('visibilitychange', onVisibility)
    document.addEventListener('click', onClick)
    window.addEventListener('error', onError)
    window.addEventListener('unhandledrejection', onRejection)

    return () => {
      window.clearInterval(interval)
      document.removeEventListener('visibilitychange', onVisibility)
      document.removeEventListener('click', onClick)
      window.removeEventListener('error', onError)
      window.removeEventListener('unhandledrejection', onRejection)
      if (activeEnqueue === enqueue) activeEnqueue = null
      void drain()
    }
  }, [enabled, role, sessionId, userId])

  useEffect(() => {
    if (!enabled) return
    const navigation = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming | undefined
    const routeStart = window.__tavaNavigationStart
    const loadMs = routeStart == null
      ? navigation?.duration ?? performance.now()
      : performance.now() - routeStart
    window.__tavaNavigationStart = undefined
    trackAnalyticsEvent({
      eventType: 'screen_view',
      name: normalisePath(pathname),
      properties: { load_ms: Math.max(0, Math.round(loadMs)) },
    })
  }, [enabled, pathname])

  return null
}
