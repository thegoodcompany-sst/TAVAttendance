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

type AnalyticsContext = {
  userId: string
  role: string
  sessionId: string
  appVersion: string | null
  device: string | null
}

let context: AnalyticsContext | null = null
const buffer: Array<Record<string, unknown>> = []
let flushing = false

const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/gi
const EMAIL = /\b[^\s@]+@[^\s@]+\.[^\s@]+\b/g

function normalisePath(path: string): string {
  return path.replace(UUID, '{id}').replace(/\/\d+(?=\/|$)/g, '/{id}')
}

export function redactAnalyticsText(value: unknown): string {
  const message = value instanceof Error ? value.message : String(value ?? 'Unknown error')
  return message.replace(EMAIL, '[email]').replace(UUID, '{id}').slice(0, 200)
}

export function trackAnalyticsEvent({ eventType, name, properties = {} }: EventInput) {
  if (!context) return
  buffer.push({
    user_id: context.userId,
    role: context.role,
    platform: 'web',
    app_version: context.appVersion,
    session_id: context.sessionId,
    event_type: eventType,
    name,
    properties,
    device: context.device,
  })
}

async function flush() {
  if (flushing || buffer.length === 0) return
  flushing = true
  const batch = buffer.splice(0)
  try {
    await createClient().from('app_events').insert(batch)
  } catch {
    // Analytics must never interfere with attendance work.
  } finally {
    flushing = false
  }
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

    context = {
      userId,
      role,
      sessionId,
      appVersion: process.env.NEXT_PUBLIC_APP_VERSION ?? null,
      device: navigator.platform || null,
    }

    trackAnalyticsEvent({ eventType: 'ops', name: 'app_launch', properties: { cold: true } })

    const interval = window.setInterval(flush, 15_000)
    const onVisibility = () => {
      if (document.visibilityState === 'hidden') void flush()
    }
    const onClick = (event: MouseEvent) => {
      const element = event.target instanceof Element
        ? event.target.closest<HTMLElement>('[data-analytics],button,a')
        : null
      if (!element) return
      const label = element.dataset.analytics
        ?? element.getAttribute('aria-label')
        ?? element.textContent
      const cleaned = label?.replace(/\s+/g, ' ').trim().slice(0, 80)
      if (!cleaned) return
      trackAnalyticsEvent({
        eventType: 'tap',
        name: `${element.tagName.toLowerCase()}:${cleaned}`,
        properties: { path: normalisePath(location.pathname) },
      })
    }
    const onError = (event: ErrorEvent) => {
      trackAnalyticsEvent({
        eventType: 'crash',
        name: 'crash_detected',
        properties: { mechanism: 'window.onerror', reason: redactAnalyticsText(event.error ?? event.message) },
      })
    }
    const onRejection = (event: PromiseRejectionEvent) => {
      trackAnalyticsEvent({
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
      void flush()
      context = null
    }
  }, [enabled, role, sessionId, userId])

  useEffect(() => {
    if (!enabled) return
    const navigation = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming | undefined
    trackAnalyticsEvent({
      eventType: 'screen_view',
      name: normalisePath(pathname),
      properties: { load_ms: Math.round(navigation?.duration ?? performance.now()) },
    })
  }, [enabled, pathname])

  return null
}
