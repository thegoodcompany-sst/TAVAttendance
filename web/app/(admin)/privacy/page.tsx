import Link from 'next/link'
import { ArrowLeft, ShieldCheck } from 'lucide-react'
import { getPrivacyNotice } from '@/lib/queries'

export const dynamic = 'force-dynamic'

export default async function PrivacyPage() {
  const notice = await getPrivacyNotice()

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <Link
        href="/"
        className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors"
      >
        <ArrowLeft size={14} />
        Back to dashboard
      </Link>

      <div className="bg-white rounded-3xl p-8 shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)]">
        <div className="flex items-center gap-3 mb-5">
          <div className="w-10 h-10 rounded-xl bg-brand-soft flex items-center justify-center">
            <ShieldCheck size={20} className="text-brand" />
          </div>
          <div>
            <h1 className="text-xl font-bold">
              {notice?.title ?? 'Data Protection Notice'}
            </h1>
            {notice && (
              <p className="text-xs text-muted-foreground mt-0.5">
                Version {notice.version} ·{' '}
                {new Date(notice.publishedAt).toLocaleDateString('en-SG', {
                  day: 'numeric',
                  month: 'long',
                  year: 'numeric',
                  timeZone: 'Asia/Singapore',
                })}
              </p>
            )}
          </div>
        </div>

        {notice ? (
          <div className="prose prose-sm max-w-none text-sm leading-relaxed text-foreground whitespace-pre-wrap">
            {notice.body}
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">
            No data protection notice has been published yet.
          </p>
        )}
      </div>
    </div>
  )
}
