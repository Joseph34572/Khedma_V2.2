import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { toChildRow } from "@/lib/childRow";
import { QuickStats } from "@/components/children/QuickStats";
import { STAGE_LABELS, type Stage } from "@/lib/roles";
import { Icon, type IconName } from "@/components/ui/Icon";

const TILES: { href: string; label: string; icon: IconName; desc: string }[] = [
  { href: "/servant/children", label: "أولادي", icon: "users", desc: "جدول متابعة أولاد مرحلتك" },
  { href: "/servant/attendance", label: "تسجيل حضور", icon: "clipboard", desc: "قداسات ومدارس الأحد" },
  { href: "/servant/prayer", label: "الصلاة", icon: "cross", desc: "إدارة محتوى الصلاة" },
  { href: "/servant/bible", label: "الكتاب المقدس", icon: "book", desc: "إدارة محتوى الكتاب المقدس" },
  { href: "/servant/quizzes", label: "المسابقات", icon: "trophy", desc: "إنشاء ومتابعة المسابقات" },
  { href: "/servant/symposium", label: "صندوق الندوة", icon: "chat", desc: "أسئلة أولاد مرحلتك" }
];

export default async function ServantHomePage() {
  const { supabase, user, fullName, stageId } = await getCurrentProfile();
  if (!user) redirect("/login");

  const { data: summary } = await supabase.from("child_activity_summary").select("*").order("full_name", { ascending: true });
  const rows = (summary ?? []).map(toChildRow);

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-xl font-extrabold text-ink">نظرة سريعة على مرحلتك</h1>
        <p className="text-ink-soft text-sm mt-1">
          متابعة أولاد {stageId ? STAGE_LABELS[stageId as Stage] : "مرحلتك"} اليوم
        </p>
      </div>

      <QuickStats rows={rows} />

      <div className="grid gap-3 sm:grid-cols-3">
        {TILES.map((t) => (
          <Link key={t.href} href={t.href} prefetch={false} className="rounded-card border border-line bg-white p-4 hover:border-primary transition-colors">
            <span className="mb-2 flex h-10 w-10 items-center justify-center rounded-xl bg-[#F4E6D3] text-primary"><Icon name={t.icon} size={20} /></span>
            <p className="font-bold text-ink">{t.label}</p>
            <p className="text-ink-soft text-xs mt-1">{t.desc}</p>
          </Link>
        ))}
      </div>
    </div>
  );
}
