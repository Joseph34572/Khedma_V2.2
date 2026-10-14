/**
 * سكريبت لإنشاء مجموعة من حسابات الخدام/الأمناء دفعة واحدة (قائمة ثابتة مكتوبة
 * هنا تحت STAFF). كلمة مرور كل حساب = رقم الموبايل المحلي زي ما هو (0 في الأول،
 * من غير +20 ومن غير مسافات)، مثال: "+20 128 033 3370" → "01280333370".
 *
 * الاستخدام (بعد ما تتأكد إن قائمة STAFF تحت مظبوطة):
 *   node --env-file=.env.local scripts/create-staff-batch.mjs
 *
 * يتطلب متغيرات البيئة: NEXT_PUBLIC_SUPABASE_URL و SUPABASE_SERVICE_ROLE_KEY
 *
 * ملاحظات:
 * - لو رقم هاتف موجود بالفعل في النظام، السكريبت بيتخطّى الشخص ده ويكمل الباقي
 *   (آمن تشغّله أكتر من مرة لو حصل خطأ في النص وعايز تعيد المحاولة).
 * - في الآخر بيطبع جدول بكل حساب اتعمل ورقمه وكلمة مروره عشان تبعتها للخدام.
 */
import { createClient } from "@supabase/supabase-js";

// role: "general_secretary" | "stage_secretary" | "servant"
// stage: "prep1" (أولى) | "prep2" (ثانية) | "prep3" (ثالثة) | null (بدون مرحلة)
const STAFF = [
  { name: "رامز زاهر", role: "general_secretary", stage: null, phone: "+20 128 033 3370" },
  { name: "ميخائيل ملاك", role: "general_secretary", stage: null, phone: "+20 128 694 3308" },

  { name: "جان فرج", role: "stage_secretary", stage: "prep1", phone: "+20 128 889 6625" },
  { name: "رامي عياد", role: "servant", stage: "prep1", phone: "+20 127 309 6870" },
  { name: "ابراهيم سمير", role: "servant", stage: "prep1", phone: "+20 155 828 7745" },
  { name: "فادي ابو اليمين", role: "servant", stage: "prep1", phone: "+20 120 717 1818" },
  { name: "انطون جمال", role: "servant", stage: "prep1", phone: "+20 114 281 4242" },
  { name: "يوحنا جورج", role: "servant", stage: "prep1", phone: "+20 122 998 5528" },
  { name: "بيشوي رضا", role: "servant", stage: "prep1", phone: "+20 155 075 2784" },
  { name: "فادي فرج", role: "servant", stage: "prep1", phone: "+20 150 867 2229" },

  { name: "ميكائيل ابراهيم", role: "stage_secretary", stage: "prep2", phone: "+20 120 125 6793" },
  { name: "ابراهيم عياد", role: "stage_secretary", stage: "prep2", phone: "+20 122 466 6582" },
  { name: "ساهر عيسى", role: "servant", stage: "prep2", phone: "+20 115 651 2349" },
  { name: "موسى شنوده", role: "servant", stage: "prep2", phone: "+20 122 660 8807" },
  { name: "يوسف سامي سمير", role: "servant", stage: "prep2", phone: "+20 122 272 8919" },
  { name: "فادي وسيم", role: "servant", stage: "prep2", phone: "+20 127 897 2540" },
  { name: "ماركو روماني", role: "servant", stage: "prep2", phone: "+20 121 776 1416" },

  { name: "بيشوي اشرف", role: "stage_secretary", stage: "prep3", phone: "+20 120 468 5784" },
  { name: "أبانوب مجدي", role: "stage_secretary", stage: "prep3", phone: "+20 122 319 5663" },
  { name: "فيلوباتير مدحت", role: "servant", stage: "prep3", phone: "+20 128 897 6488" },
  { name: "بيشوي مخلص", role: "servant", stage: "prep3", phone: "+20 122 762 7390" },
  { name: "جون شوكت", role: "servant", stage: "prep3", phone: "+20 128 333 1217" }
];

/** نفس منطق التطبيع المستخدم في باقي التطبيق (phone_normalized = "20" + 10 أرقام). */
function normalizePhone(raw) {
  let digits = raw.replace(/[^\d]/g, "");
  if (digits.startsWith("00")) digits = digits.slice(2);
  if (digits.length === 11 && digits.startsWith("0")) digits = "20" + digits.slice(1);
  if (digits.length === 10 && digits.startsWith("1")) digits = "20" + digits;
  return digits;
}

/** كلمة المرور = الرقم المحلي زي ما هو (0 في الأول)، مش الصيغة الدولية المخزَّنة. */
function localPasswordFromPhone(raw) {
  const digits = raw.replace(/[^\d]/g, ""); // "201280333370"
  const local = digits.startsWith("20") ? "0" + digits.slice(2) : digits; // "01280333370"
  return local;
}

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { autoRefreshToken: false, persistSession: false } }
);

const results = [];

for (const person of STAFF) {
  const normalized = normalizePhone(person.phone);
  const password = localPasswordFromPhone(person.phone);
  const email = `${normalized}@phone.khedma.internal`;

  const { data: existingProfile } = await supabase
    .from("profiles")
    .select("id")
    .eq("phone_normalized", normalized)
    .maybeSingle();

  if (existingProfile) {
    console.log(`⏭  تخطّي "${person.name}" — رقم الهاتف موجود بالفعل في النظام.`);
    results.push({ ...person, password, status: "موجود بالفعل (تم التخطّي)" });
    continue;
  }

  const { data: created, error: createError } = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true
  });

  if (createError || !created.user) {
    console.error(`❌ فشل إنشاء حساب "${person.name}":`, createError?.message);
    results.push({ ...person, password, status: `فشل: ${createError?.message ?? "خطأ غير معروف"}` });
    continue;
  }

  const { error: profileError } = await supabase.from("profiles").insert({
    id: created.user.id,
    full_name: person.name,
    phone_normalized: normalized,
    role: person.role,
    stage_id: person.stage
  });

  if (profileError) {
    console.error(`❌ فشل حفظ بروفايل "${person.name}":`, profileError.message);
    await supabase.auth.admin.deleteUser(created.user.id);
    results.push({ ...person, password, status: `فشل حفظ البروفايل: ${profileError.message}` });
    continue;
  }

  console.log(`✅ تم إنشاء "${person.name}"`);
  results.push({ ...person, password, status: "تم الإنشاء بنجاح" });
}

console.log("\n=== ملخّص الحسابات ===");
console.table(
  results.map((r) => ({
    الاسم: r.name,
    الدور: r.role,
    المرحلة: r.stage ?? "—",
    "رقم الدخول": localPasswordFromPhone(r.phone),
    الحالة: r.status
  }))
);
