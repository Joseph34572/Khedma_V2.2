import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { canManageUsers, ROLE_LABELS, type AppRole } from "@/lib/roles";
import { relativeArabicDate } from "@/lib/format";

const ACTION_LABELS: Record<string, string> = {
  login: "تسجيل دخول",
  create_user: "إنشاء مستخدم",
  update_user: "تعديل مستخدم",
  disable_user: "تعطيل مستخدم",
  enable_user: "إعادة تفعيل مستخدم",
  delete_user: "حذف حساب نهائيًا",
  reset_password: "تغيير كلمة مرور",
  create_mass: "إنشاء قداس",
  delete_mass: "حذف قداس",
  delete_sunday_school_session: "حذف جلسة مدارس أحد",
  create_quiz: "إنشاء مسابقة",
  delete_quiz: "حذف مسابقة",
  grade_attempt: "تصحيح إجابة",
  change_question_status: "تغيير حالة سؤال",
  assign_question: "تعيين سؤال لخادم",
  send_notification: "إرسال إشعار",
  import_bible_chapter: "استيراد إصحاح"
};

// عمليات "حساسة" (حذف/تعطيل/حذف حساب) بتتلوّن باللون التحذيري عشان تلفت النظر بسرعة.
const SENSITIVE_ACTIONS = new Set(["delete_user", "disable_user", "delete_mass", "delete_sunday_school_session", "delete_quiz"]);

type AuditRow = {
  id: string;
  action: string;
  entity_type: string;
  entity_id: string | null;
  details: Record<string, unknown>;
  created_at: string;
  actor_id: string | null;
  actor: { full_name: string; role: AppRole } | { full_name: string; role: AppRole }[] | null;
};

function actorOf(row: AuditRow): { full_name: string; role: AppRole } | null {
  if (!row.actor) return null;
  return Array.isArray(row.actor) ? (row.actor[0] ?? null) : row.actor;
}

export default async function AuditLogPage() {
  const { supabase, user, role } = await getCurrentProfile();
  if (!user) redirect("/login");
  if (!role || !canManageUsers(role)) redirect("/admin");

  const { data: log } = await supabase
    .from("audit_log")
    .select("id, action, entity_type, entity_id, details, created_at, actor_id, actor:profiles!audit_log_actor_id_fkey(full_name, role)")
    .order("created_at", { ascending: false })
    .limit(150);

  const rows = (log ?? []) as unknown as AuditRow[];

  return (
    <div>
      <div className="mb-4">
        <h1 className="text-xl font-extrabold text-ink">سجل العمليات</h1>
        <p className="text-sm text-ink-soft mt-1">آخر {rows.length} عملية — من دخل ومين عمل ايه، بما فيها عمليات الحذف والتعطيل الحساسة.</p>
      </div>

      <div className="rounded-card border border-line bg-white divide-y divide-line overflow-hidden">
        {rows.length === 0 && <p className="text-center text-ink-soft py-10">لا توجد عمليات مسجّلة بعد.</p>}

        {rows.map((entry) => {
          const actor = actorOf(entry);
          const sensitive = SENSITIVE_ACTIONS.has(entry.action);
          const detailsText = Object.keys(entry.details ?? {}).length > 0 ? JSON.stringify(entry.details) : null;

          return (
            <div key={entry.id} className="flex items-start gap-3 px-4 py-3">
              <div
                className={`mt-0.5 h-2.5 w-2.5 rounded-full flex-shrink-0 ${sensitive ? "bg-bad" : "bg-gold"}`}
                aria-hidden
              />
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
                  <span className={`font-bold text-sm ${sensitive ? "text-bad" : "text-ink"}`}>
                    {ACTION_LABELS[entry.action] ?? entry.action}
                  </span>
                  <span className="text-ink-soft text-xs">
                    {actor ? (
                      <>
                        بواسطة <span className="font-semibold text-ink">{actor.full_name}</span>
                        <span className="text-ink-soft"> ({ROLE_LABELS[actor.role]})</span>
                      </>
                    ) : (
                      "بواسطة مستخدم محذوف"
                    )}
                  </span>
                </div>
                {detailsText && (
                  <p className="text-xs text-ink-soft mt-1 break-all" dir="ltr">
                    {detailsText}
                  </p>
                )}
              </div>
              <span className="text-xs text-ink-soft whitespace-nowrap flex-shrink-0">{relativeArabicDate(entry.created_at)}</span>
            </div>
          );
        })}
      </div>

      <p className="text-xs text-ink-soft mt-3">
        السجل يحتفظ تلقائيًا بعمليات آخر 180 يوم فقط، عشان يفضل خفيف ومرتّب.
      </p>
    </div>
  );
}
