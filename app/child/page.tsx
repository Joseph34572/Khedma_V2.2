import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { relativeArabicDate } from "@/lib/format";

// محيط دايرة التقدّم (نصف القطر 34) — لازم يطابق --ring-full في الـ style تحت.
const RING_CIRCUMFERENCE = 2 * Math.PI * 34;

export default async function ChildHomePage() {
  const { supabase, user } = await getCurrentProfile();
  if (!user) redirect("/login");

  const [{ data: lastPrayer }, { data: lastReading }, { data: lastMass }, { data: lastConfession }, { data: lastSunday }] =
    await Promise.all([
      supabase
        .from("prayer_sessions")
        .select("started_at, completion_level")
        .eq("user_id", user.id)
        .order("started_at", { ascending: false })
        .limit(1)
        .maybeSingle(),
      supabase
        .from("bible_reading_sessions")
        .select("started_at, completion_level")
        .eq("user_id", user.id)
        .order("started_at", { ascending: false })
        .limit(1)
        .maybeSingle(),
      supabase
        .from("mass_attendance")
        .select("created_at")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle(),
      supabase
        .from("confessions")
        .select("confessed_at")
        .eq("user_id", user.id)
        .order("confessed_at", { ascending: false })
        .limit(1)
        .maybeSingle(),
      supabase
        .from("sunday_school_attendance")
        .select("recorded_at")
        .eq("user_id", user.id)
        .order("recorded_at", { ascending: false })
        .limit(1)
        .maybeSingle()
    ]);

  const today = new Date().toDateString();
  const isToday = (value: string | undefined) => !!value && new Date(value).toDateString() === today;
  const prayedToday = isToday(lastPrayer?.started_at) && lastPrayer?.completion_level === "likely_complete";
  const readToday = isToday(lastReading?.started_at) && lastReading?.completion_level === "likely_complete";

  const done = Number(prayedToday) + Number(readToday);
  const total = 2;
  const ringOffset = RING_CIRCUMFERENCE * (1 - done / total);
  const ar = (n: number) => n.toLocaleString("ar-EG");

  const headline = done === total ? "برافو! خلّصت مهام النهارده" : done > 0 ? "قربت تخلّص!" : "يلا نبدأ اليوم";
  const subline =
    done === total
      ? "صلّيت وقريت الإصحاح، ربنا يباركك"
      : !prayedToday && !readToday
        ? "صلاة النهارده وقراية الإصحاح مستنيينك"
        : !prayedToday
          ? "فاضلك صلاة النهارده وتكمّل مهامك"
          : "فاضلك قراءة الإصحاح وتكمّل مهامك";

  return (
    <div className="max-w-xl grid grid-cols-2 gap-3">
      <section className="col-span-2 bg-white rounded-[24px] border-2 border-line p-4 flex items-center gap-4 shadow-[0_6px_0_#ECDFC8]">
        <div className="relative h-[84px] w-[84px] flex-none">
          <svg aria-hidden width="84" height="84" viewBox="0 0 84 84">
            <circle cx="42" cy="42" r="34" fill="none" stroke="#F4E6D3" strokeWidth="10" />
            <circle
              className="anim-ring"
              cx="42"
              cy="42"
              r="34"
              fill="none"
              stroke="#7A1F2B"
              strokeWidth="10"
              strokeLinecap="round"
              strokeDasharray={RING_CIRCUMFERENCE}
              transform="rotate(-90 42 42)"
              style={{ strokeDashoffset: ringOffset, ["--ring-full" as string]: RING_CIRCUMFERENCE }}
            />
          </svg>
          <span className="absolute inset-0 flex items-center justify-center text-[21px] font-extrabold text-primary">
            {ar(done)}/{ar(total)}
          </span>
        </div>
        <div className="min-w-0">
          <h1 className="text-[17px] font-extrabold text-ink">{headline}</h1>
          <p className="text-sm text-ink-soft leading-relaxed mt-1">{subline}</p>
        </div>
      </section>

      <StatusCard label="الصلاة" icon={<CrossIcon />}>
        {prayedToday ? <Done>مكتملة النهارده</Done> : <Pending>لم تكتمل بعد</Pending>}
      </StatusCard>
      <StatusCard label="الكتاب المقدس" icon={<BookIcon />}>
        {readToday ? <Done>قريت النهارده</Done> : <Pending>لم يكتمل بعد</Pending>}
      </StatusCard>
      <StatusCard label="القداس" icon={<CalendarIcon />}>
        <span className="text-[13px] text-ink-soft">
          {lastMass ? `آخر حضور: ${relativeArabicDate(lastMass.created_at)}` : "لم يتم التسجيل"}
        </span>
      </StatusCard>
      <StatusCard label="مدارس الأحد" icon={<UsersIcon />}>
        <span className="text-[13px] text-ink-soft">
          {lastSunday ? `آخر حضور: ${relativeArabicDate(lastSunday.recorded_at)}` : "لم يسجّل بعد"}
        </span>
      </StatusCard>
      <StatusCard label="الاعتراف" icon={<HeartIcon />} wide>
        <span className="text-[13px] text-ink-soft">{relativeArabicDate(lastConfession?.confessed_at ?? null)}</span>
      </StatusCard>

      <Link
        href="/child/prayer"
        prefetch={false}
        className="h-[54px] rounded-[18px] bg-primary text-parchment text-base font-extrabold flex items-center justify-center mt-1.5"
      >
        ابدأ الصلاة
      </Link>
      <Link
        href="/child/bible"
        prefetch={false}
        className="h-[54px] rounded-[18px] bg-gold text-ink text-base font-extrabold flex items-center justify-center mt-1.5"
      >
        اقرأ الإصحاح
      </Link>
    </div>
  );
}

function StatusCard({
  label,
  icon,
  wide = false,
  children
}: {
  label: string;
  icon: React.ReactNode;
  wide?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div
      className={`playful-card bg-white rounded-[20px] border-2 border-line p-3.5 shadow-[0_5px_0_#ECDFC8] ${
        wide ? "col-span-2 flex items-center gap-3" : "flex flex-col gap-2"
      }`}
    >
      <span className="h-[38px] w-[38px] flex-none rounded-xl bg-[#F4E6D3] flex items-center justify-center text-primary">{icon}</span>
      <span className={`text-[15px] font-bold text-ink ${wide ? "flex-1" : ""}`}>{label}</span>
      {children}
    </div>
  );
}

// الحالة دايمًا بأيقونة + نص (مش لون بس)، زي باقي التطبيق.
function Done({ children }: { children: React.ReactNode }) {
  return (
    <span className="text-[13px] font-bold text-good flex items-center gap-1">
      <svg aria-hidden width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
        <path className="anim-check" d="M5 12l5 5 9-10" />
      </svg>
      {children}
    </span>
  );
}

function Pending({ children }: { children: React.ReactNode }) {
  return (
    <span className="text-[13px] font-bold text-[#8A5A00] flex items-center gap-1">
      <span className="anim-tick">
        <svg aria-hidden width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
          <circle cx="12" cy="12" r="9" />
          <path d="M12 7v5l3 2" />
        </svg>
      </span>
      {children}
    </span>
  );
}

function Svg({ children }: { children: React.ReactNode }) {
  return (
    <svg aria-hidden width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
      {children}
    </svg>
  );
}
const CrossIcon = () => <Svg><path d="M12 3v18M6.5 8.5h11" /></Svg>;
const BookIcon = () => <Svg><path d="M4 5a2 2 0 0 1 2-2h13v15H6a2 2 0 0 0-2 2z" /><path d="M4 20a2 2 0 0 0 2 1h13v-3" /></Svg>;
const CalendarIcon = () => <Svg><rect x="3" y="5" width="18" height="16" rx="2" /><path d="M3 10h18M8 3v4M16 3v4" /></Svg>;
const UsersIcon = () => (
  <Svg>
    <circle cx="9" cy="8" r="3.5" />
    <path d="M2.5 20c1-3.5 3.5-5 6.5-5s5.5 1.5 6.5 5M16 4.5a3.5 3.5 0 0 1 0 7M18 15c2 .6 3.2 2.2 3.5 5" />
  </Svg>
);
const HeartIcon = () => <Svg><path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z" /></Svg>;
