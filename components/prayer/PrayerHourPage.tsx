import { notFound, redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { PrayerRunner } from "@/components/PrayerRunner";
import { AgpeyaReader } from "@/components/prayer/AgpeyaReader";

/**
 * صفحة صلاة واحدة (للولد والخادم): لو الصلاة متقسّمة لأجزاء (prayer_sections) بتفتح
 * قارئ الأجبية بالأجزاء والسحب، ولو لسه نص واحد بس بتفتح PrayerRunner القديم.
 */
export async function PrayerHourPage({ prayerId, backHref }: { prayerId: string; backHref: string }) {
  const { supabase, user } = await getCurrentProfile();
  if (!user) redirect("/login");

  const [{ data: prayer }, { data: sections }] = await Promise.all([
    supabase.from("prayer_contents").select("id, title_ar, body_ar").eq("id", prayerId).eq("is_active", true).maybeSingle(),
    supabase.from("prayer_sections").select("id, title_ar, body_ar").eq("prayer_content_id", prayerId).order("sort_order")
  ]);

  if (!prayer) notFound();

  const parts = (sections ?? []).filter((s) => s.body_ar.trim());
  if (parts.length > 0) {
    return (
      <AgpeyaReader
        prayerContentId={prayer.id}
        title={prayer.title_ar}
        sections={parts.map((s) => ({ id: s.id, title: s.title_ar, body: s.body_ar }))}
        backHref={backHref}
      />
    );
  }

  return <PrayerRunner prayerContentId={prayer.id} title={prayer.title_ar} body={prayer.body_ar} backHref={backHref} />;
}
