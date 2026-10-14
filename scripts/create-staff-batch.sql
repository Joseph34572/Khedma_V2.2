-- ============================================================================
-- إنشاء حسابات الخدام/الأمناء دفعة واحدة مباشرة من SQL Editor في Supabase.
-- كلمة مرور كل حساب = رقم الموبايل المحلي (0 في الأول، من غير +20 ومن غير
-- مسافات)، مثال: "+20 128 033 3370" → كلمة المرور "01280333370".
--
-- تحذير: الطريقة دي بتكتب مباشرة في جداول auth.users و auth.identities
-- الداخلية بتاعة Supabase، وهي أكثر حساسية لاختلافات الإصدار من استخدام
-- Admin API (البديل الموجود في scripts/create-staff-batch.mjs). ينصح تجرّب
-- شخص واحد بس الأول (نفّذ الكويري وبعدين جرّب تسجيل دخول بيه فعليًا) قبل ما
-- تشغّل الدفعة كاملة.
--
-- شغّلها من: Supabase Dashboard → SQL Editor → New query → الصق الكود كله
-- واضغط Run مرة واحدة.
-- ============================================================================

create extension if not exists pgcrypto;

do $$
declare
  -- كل صف: (الاسم, رقم الهاتف كما هو مكتوب, الدور, المرحلة أو NULL)
  staff record;
  staff_list text[][] := array[
    array['رامز زاهر',        '+20 128 033 3370', 'general_secretary', null],
    array['ميخائيل ملاك',      '+20 128 694 3308', 'general_secretary', null],

    array['جان فرج',          '+20 128 889 6625', 'stage_secretary',   'prep1'],
    array['رامي عياد',        '+20 127 309 6870', 'servant',           'prep1'],
    array['ابراهيم سمير',      '+20 155 828 7745', 'servant',           'prep1'],
    array['فادي ابو اليمين',   '+20 120 717 1818', 'servant',           'prep1'],
    array['انطون جمال',       '+20 114 281 4242', 'servant',           'prep1'],
    array['يوحنا جورج',       '+20 122 998 5528', 'servant',           'prep1'],
    array['بيشوي رضا',        '+20 155 075 2784', 'servant',           'prep1'],
    array['فادي فرج',         '+20 150 867 2229', 'servant',           'prep1'],

    array['ميكائيل ابراهيم',   '+20 120 125 6793', 'stage_secretary',   'prep2'],
    array['ابراهيم عياد',      '+20 122 466 6582', 'stage_secretary',   'prep2'],
    array['ساهر عيسى',        '+20 115 651 2349', 'servant',           'prep2'],
    array['موسى شنوده',       '+20 122 660 8807', 'servant',           'prep2'],
    array['يوسف سامي سمير',    '+20 122 272 8919', 'servant',           'prep2'],
    array['فادي وسيم',        '+20 127 897 2540', 'servant',           'prep2'],
    array['ماركو روماني',      '+20 121 776 1416', 'servant',           'prep2'],

    array['بيشوي اشرف',       '+20 120 468 5784', 'stage_secretary',   'prep3'],
    array['أبانوب مجدي',      '+20 122 319 5663', 'stage_secretary',   'prep3'],
    array['فيلوباتير مدحت',    '+20 128 897 6488', 'servant',           'prep3'],
    array['بيشوي مخلص',       '+20 122 762 7390', 'servant',           'prep3'],
    array['جون شوكت',         '+20 128 333 1217', 'servant',           'prep3']
  ];
  i int;
  v_name text;
  v_phone_raw text;
  v_role text;
  v_stage text;
  v_digits text;
  v_local text;      -- كلمة المرور: 01280333370
  v_normalized text;  -- للتخزين: 201280333370
  v_email text;
  v_user_id uuid;
begin
  for i in 1 .. array_length(staff_list, 1) loop
    v_name  := staff_list[i][1];
    v_phone_raw := staff_list[i][2];
    v_role  := staff_list[i][3];
    v_stage := staff_list[i][4];

    -- استخراج الأرقام بس من النص (شيل +، المسافات، إلخ)
    v_digits := regexp_replace(v_phone_raw, '[^0-9]', '', 'g'); -- "201280333370"
    v_local := '0' || substring(v_digits from 3);                -- "01280333370"
    v_normalized := v_digits;                                    -- "201280333370"
    v_email := v_normalized || '@phone.khedma.internal';

    -- تخطّي لو الرقم موجود بالفعل (يخلي تشغيل الكود تاني آمن لو حصل خطأ وعايز تعيد المحاولة)
    if exists (select 1 from public.profiles where phone_normalized = v_normalized) then
      raise notice 'تخطّي % — الرقم موجود بالفعل.', v_name;
      continue;
    end if;

    v_user_id := gen_random_uuid();

    insert into auth.users (
      instance_id, id, aud, role, email,
      encrypted_password, email_confirmed_at,
      recovery_sent_at, last_sign_in_at,
      raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at,
      confirmation_token, email_change, email_change_token_new, recovery_token
    ) values (
      '00000000-0000-0000-0000-000000000000',
      v_user_id, 'authenticated', 'authenticated', v_email,
      crypt(v_local, gen_salt('bf')), now(),
      null, null,
      '{"provider":"email","providers":["email"]}', '{}',
      now(), now(),
      '', '', '', ''
    );

    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), v_user_id, v_user_id::text,
      jsonb_build_object('sub', v_user_id::text, 'email', v_email),
      'email', now(), now(), now()
    );

    insert into public.profiles (id, full_name, phone_normalized, role, stage_id)
    values (v_user_id, v_name, v_normalized, v_role::public.app_role, v_stage::public.app_stage);

    raise notice 'تم إنشاء % — رقم الدخول: %  كلمة المرور: %', v_name, v_local, v_local;
  end loop;
end $$;
