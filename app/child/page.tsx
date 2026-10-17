import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { relativeArabicDate } from "@/lib/format";
import { Icon, type IconName } from "@/components/ui/Icon";

// محيط دايرة التقدّم (نصف القطر 34) — بيتمرّر كمان لـ --ring-full عشان حركة الملء.
const RING_CIRCUMFERENCE = 2 * Math.PI * 34;

type NotificationRow = { id: string; notifications: { title: string; sent_at: string | null } | null };

export default async function ChildHomePage() {
  const { supabase, user } = await getCurrentProfile();
  if (!user) redirect("/login");

  const nowIso = new Date().toISOString();

  const [
    { data: lastPrayer },
    { data: lastReading },
    { data: lastConfession },
    { data: lastSunday },
    { data: openQuizzes },
    { data: myAttempts },
    { data: unread }
  ] = await Promise.all([
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
      .from("confessions")
      .select("confessed_at")
      .eq("user_id", user.id)
      .order("confessed_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
    supabase
      .from("sunday_school_attendance")
      .select("recorded_at, sunday_school_sessions(session_date)")
      .eq("user_id", user.id)
      .order("recorded_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
    // المسابقات المفتوحة دلوقتي (RLS بيقصرها على مرحلة الولد).
    supabase
      .from("quizzes")
      .select("id, title_ar, ends_at, max_attempts")
      .lte("starts_at", nowIso)
      .gte("ends_at", nowIso)
      .order("ends_at", { ascending: true }),
    supabase.from("quiz_attempts").select("quiz_id, submitted_at").eq("user_id", user.id),
    // الإشعارات اللي لسه متقرتش — أول ما الولد يقرأها الكارت بيختفي.
    supabase
      .from("notification_recipients")
      .select("id, notifications(title, sent_at)")
      .eq("user_id", user.id)
      .is("read_at", null)
      .limit(50)
  ]);

  const today = new Date().toDateString();
  const isToday = (value: string | undefined) => !!value && new Date(value).toDateString() === today;
  const prayedToday = isToday(lastPrayer?.started_at) && lastPrayer?.completion_level === "likely_complete";
  const readToday = isToday(lastReading?.started_at) && lastReading?.completion_level === "likely_complete";

  // تاريخ حصة مدارس الأحد نفسها لو متاح؛ الولد مالوش صلاحية قراءة جدول الحصص (RLS)،
  // فوقتها بنرجع لوقت تسجيل الحضور.
  const sundaySession = lastSunday?.sunday_school_sessions as unknown as { session_date: string } | null | undefined;
  const lastSundayDate = sundaySession?.session_date ?? lastSunday?.recorded_at ?? null;

  // مسابقة تظهر بس لو مفتوحة الآن والولد لسه عنده محاولات.
  const submittedByQuiz = new Map<string, number>();
  for (const a of myAttempts ?? []) {
    if (a.submitted_at) submittedByQuiz.set(a.quiz_id, (submittedByQuiz.get(a.quiz_id) ?? 0) + 1);
  }
  const availableQuizzes = (openQuizzes ?? []).filter((q) => (submittedByQuiz.get(q.id) ?? 0) < (q.max_attempts ?? 1));

  const firstQuiz = availableQuizzes[0];

  const unreadItems = ((unread ?? []) as unknown as NotificationRow[]).filter((r) => r.notifications);
  const latestUnread = unreadItems.sort((a, b) =>
    (b.notifications?.sent_at ?? "").localeCompare(a.notifications?.sent_at ?? "")
  )[0];

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
          ? "فاضلك صلاة النهارده"
          : "فاضلك قراءة الإصحاح";

  return (
    <div className="max-w-xl mx-auto grid grid-cols-2 gap-3">
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

      <Tile href="/child/prayer" label="الصلاة" icon="cross">
        {prayedToday ? <Done>مكتملة النهارده</Done> : <Pending>لم تكتمل بعد</Pending>}
      </Tile>
      <Tile href="/child/bible" label="الكتاب المقدس" icon="book">
        {readToday ? <Done>قريت النهارده</Done> : <Pending>لم يكتمل بعد</Pending>}
      </Tile>
      <Tile href="/child/mass" label="مدارس الأحد" icon="users">
        <Muted>{lastSundayDate ? `آخر حضور: ${relativeArabicDate(lastSundayDate)}` : "لم يسجّل بعد"}</Muted>
      </Tile>
      <Tile label="الاعتراف" icon="heart">
        <Muted>{lastConfession ? `آخر اعتراف: ${relativeArabicDate(lastConfession.confessed_at)}` : "لم يسجّل بعد"}</Muted>
      </Tile>

      {firstQuiz && (
        <WideTile
          href={availableQuizzes.length === 1 ? `/child/quizzes/${firstQuiz.id}` : "/child/quizzes"}
          icon="trophy"
          chipClass="bg-gold text-primary-dark"
          title={availableQuizzes.length === 1 ? "مسابقة مستنياك!" : `${ar(availableQuizzes.length)} مسابقات مستنياك!`}
          subtitle={`${firstQuiz.title_ar} · تنتهي ${relativeArabicDate(firstQuiz.ends_at)}`}
        />
      )}

      {latestUnread && (
        <WideTile
          href="/child/notifications"
          icon="bell"
          chipClass="bg-primary text-parchment"
          title={unreadItems.length === 1 ? "إشعار جديد" : `${ar(unreadItems.length)} إشعارات جديدة`}
          subtitle={latestUnread.notifications?.title ?? ""}
          badge={ar(unreadItems.length)}
        />
      )}

      <Link
        href="/child/symposium"
        prefetch={false}
        className="col-span-2 h-[56px] rounded-[18px] bg-primary text-parchment text-base font-extrabold flex items-center justify-center gap-2 mt-1.5"
      >
        <Icon name="chat" size={20} />
        اسأل سؤال في صندوق الندوة
      </Link>
    </div>
  );
}

const TILE_CLASS = "bg-white rounded-[20px] border-2 border-line p-3.5 shadow-[0_5px_0_#ECDFC8] flex flex-col gap-2";

function Tile({
  href,
  label,
  icon,
  children
}: {
  href?: string;
  label: string;
  icon: IconName;
  children: React.ReactNode;
}) {
  const body = (
    <>
      <span className="flex items-start justify-between">
        <span className="h-[38px] w-[38px] rounded-xl bg-[#F4E6D3] flex items-center justify-center text-primary">
          <Icon name={icon} size={18} strokeWidth={2.2} />
        </span>
        {href && <Icon name="chevronLeft" size={18} className="text-ink-soft mt-2" />}
      </span>
      <span className="text-[15px] font-bold text-ink">{label}</span>
      {children}
    </>
  );
  return href ? (
    <Link href={href} prefetch={false} className={`playful-card ${TILE_CLASS}`}>
      {body}
    </Link>
  ) : (
    <div className={TILE_CLASS}>{body}</div>
  );
}

function WideTile({
  href,
  icon,
  chipClass,
  title,
  subtitle,
  badge
}: {
  href: string;
  icon: IconName;
  chipClass: string;
  title: string;
  subtitle: string;
  badge?: string;
}) {
  return (
    <Link
      href={href}
      prefetch={false}
      className="playful-card col-span-2 bg-white rounded-[20px] border-2 border-line p-3.5 shadow-[0_5px_0_#ECDFC8] flex items-center gap-3"
    >
      <span className={`relative h-[44px] w-[44px] flex-none rounded-xl flex items-center justify-center ${chipClass}`}>
        <Icon name={icon} size={20} strokeWidth={2.2} />
        {badge && (
          <span className="absolute -top-1.5 -left-1.5 min-w-[20px] h-5 px-1 rounded-full bg-gold text-ink text-[11px] font-extrabold flex items-center justify-center">
            {badge}
          </span>
        )}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[15px] font-extrabold text-ink">{title}</span>
        <span className="block text-[13px] text-ink-soft truncate">{subtitle}</span>
      </span>
      <Icon name="chevronLeft" size={18} className="text-ink-soft" />
    </Link>
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
        <Icon name="clock" size={14} strokeWidth={2.5} />
      </span>
      {children}
    </span>
  );
}

function Muted({ children }: { children: React.ReactNode }) {
  return <span className="text-[13px] text-ink-soft">{children}</span>;
}
