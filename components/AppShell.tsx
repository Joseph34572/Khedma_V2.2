"use client";

import { useEffect, useRef } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { signOutAction } from "@/app/actions";

export type NavItem = { href: string; label: string; icon: string };

const ROOTS = ["/admin", "/servant", "/child"];

// عرض كل زرار في شريط التنقل السفلي (بالبكسل) — الـ "حبّاية" اللي بتتزحلق تحت
// الزرار النشط بتتحسب منه، فلازم يفضل ثابت ومطابق لـ w-[76px] تحت.
const TAB_WIDTH = 76;
const PILL_WIDTH = 62;

// الـ layouts بتبعت أيقونة كـ emoji (نفس القيم القديمة)؛ هنا بنحوّلها لأيقونة SVG
// خطّية موحّدة عشان الشكل يبقى متناسق على كل الأجهزة. لو جه emoji مش في القايمة
// بيتعرض زي ما هو.
const ICON_PATHS: Record<string, string> = {
  "🏠": "M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z",
  "👥": "M9 4.5a3.5 3.5 0 1 1 0 7a3.5 3.5 0 1 1 0-7zM2.5 20c1-3.5 3.5-5 6.5-5s5.5 1.5 6.5 5M16 4.5a3.5 3.5 0 0 1 0 7M18 15c2 .6 3.2 2.2 3.5 5",
  "📋": "M9 3.5h6v3H9zM7 5H5.5A1.5 1.5 0 0 0 4 6.5v13A1.5 1.5 0 0 0 5.5 21h13a1.5 1.5 0 0 0 1.5-1.5v-13A1.5 1.5 0 0 0 18.5 5H17M8.5 13l2.5 2.5 4.5-5",
  "🕊": "M12 3v18M6.5 8.5h11",
  "📖": "M4 5a2 2 0 0 1 2-2h13v15H6a2 2 0 0 0-2 2zM4 20a2 2 0 0 0 2 1h13v-3",
  "🏆": "M8 4h8v5a4 4 0 0 1-8 0zM8 6H5a3 3 0 0 0 3 4M16 6h3a3 3 0 0 1-3 4M12 13v4M8.5 21h7M10 17h4v4",
  "💬": "M4 5h16v11H9l-5 4z",
  "🔔": "M6 16v-5a6 6 0 0 1 12 0v5l2 2H4zM10 20a2 2 0 0 0 4 0",
  "🪪": "M3 6h18v12H3zM8.5 9.5a2 2 0 1 1 0 4a2 2 0 1 1 0-4zM13 10h5M13 14h4",
  "👤": "M12 4a4 4 0 1 1 0 8a4 4 0 1 1 0-8zM4 21c1.5-4 4.5-6 8-6s6.5 2 8 6",
  "🧒": "M12 5a3 3 0 1 1 0 6a3 3 0 1 1 0-6zM6 21c.8-3.5 3.2-5.5 6-5.5s5.2 2 6 5.5",
  "🗂": "M3 6a1 1 0 0 1 1-1h5l2 2h9a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z"
};

function NavIcon({ icon, size = 22 }: { icon: string; size?: number }) {
  const d = ICON_PATHS[icon.replace(/️/g, "")];
  if (!d) return <span aria-hidden>{icon}</span>;
  return (
    <svg aria-hidden width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d={d} />
    </svg>
  );
}

export function AppShell({
  navItems,
  userName,
  roleLabel,
  children
}: {
  navItems: NavItem[];
  activeHref?: string;
  userName: string;
  roleLabel: string;
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const isActive = (href: string) =>
    ROOTS.includes(href) ? pathname === href : pathname === href || pathname.startsWith(href + "/");
  const activeIndex = navItems.findIndex((item) => isActive(item.href));
  const firstName = userName.trim().split(/\s+/)[0] ?? "";

  // لو عدد الأقسام أكبر من عرض الشاشة، الشريط السفلي بيتسكرول أفقي؛ نخلي الزرار
  // النشط يبان في النص بعد كل تنقّل.
  const bottomNavRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    bottomNavRef.current
      ?.querySelector('[aria-current="page"]')
      ?.scrollIntoView({ inline: "center", block: "nearest", behavior: "smooth" });
  }, [pathname]);

  return (
    <div className="min-h-screen lg:flex">
      <aside className="hidden lg:flex lg:w-64 lg:flex-col border-l border-line bg-white p-4">
        <div className="flex items-center gap-3 px-2 py-3 mb-4">
          <div className="h-10 w-10 -rotate-6 rounded-xl bg-gold flex items-center justify-center text-primary-dark">
            <NavIcon icon="🕊" size={20} />
          </div>
          <p className="font-extrabold text-ink leading-none">خدمة إعدادي</p>
        </div>
        <nav className="flex-1 space-y-1 overflow-y-auto">
          {navItems.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              // كل صفحات التطبيق ديناميكية وبيانات كل مستخدم خاصة به، فالـ prefetch
              // التلقائي لـ Next.js (بيحصل لحظة ظهور أي رابط في الشاشة) كان بيعمل طلب
              // حقيقي لـ Supabase لكل رابط في القائمة الجانبية على كل صفحة — ده كان
              // بيزنق اتصالات المتصفح والسيرفر ويبطّئ الطلب الحقيقي اللي المستخدم مستنيه.
              prefetch={false}
              aria-current={isActive(item.href) ? "page" : undefined}
              className={`nav-tab flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium ${
                isActive(item.href) ? "bg-primary text-white" : "text-ink-soft hover:bg-parchment"
              }`}
            >
              <NavIcon icon={item.icon} size={20} />
              {item.label}
            </Link>
          ))}
        </nav>
        <div className="border-t border-line pt-3 mt-3">
          <p className="text-sm font-bold text-ink">{userName}</p>
          <p className="text-xs text-ink-soft mb-3">{roleLabel}</p>
          <form action={signOutAction}>
            <button type="submit" className="text-sm text-bad font-medium hover:underline">تسجيل الخروج</button>
          </form>
        </div>
      </aside>

      <div className="flex-1 flex flex-col min-h-screen min-w-0">
        <header className="anim-drop relative overflow-hidden bg-primary text-parchment px-5 pt-5 pb-8 rounded-b-[32px] lg:mx-8 lg:mt-4 lg:rounded-[28px] lg:pb-6">
          <span aria-hidden className="anim-float absolute top-5 left-8 h-2.5 w-2.5 rounded-full bg-gold opacity-70" />
          <span aria-hidden className="anim-float absolute top-16 left-20 h-1.5 w-1.5 rounded-full bg-gold opacity-50 [animation-delay:0.8s]" />
          <span aria-hidden className="anim-float absolute top-24 left-5 h-3.5 w-3.5 rounded-full bg-gold opacity-35 [animation-delay:1.6s]" />
          <div className="relative flex items-center gap-3">
            <div className="h-12 w-12 flex-none -rotate-6 rounded-2xl bg-gold flex items-center justify-center text-primary-dark lg:hidden">
              <NavIcon icon="🕊" size={22} />
            </div>
            <div className="min-w-0">
              <p className="text-[13px] font-medium text-gold-light">{roleLabel}</p>
              <p className="text-[22px] font-extrabold leading-tight truncate">
                <span className="anim-wave">أهلًا {firstName}</span>
              </p>
            </div>
            <form action={signOutAction} className="ms-auto lg:hidden">
              <button
                type="submit"
                className="nav-tab flex h-11 items-center gap-1.5 rounded-full bg-parchment/15 px-4 text-sm font-bold text-parchment"
              >
                خروج
              </button>
            </form>
          </div>
        </header>

        <main className="flex-1 p-4 -mt-3 lg:mt-0 lg:p-8 pb-28 lg:pb-8">
          {/* المفتاح = المسار، فمع كل تنقّل المحتوى بيدخل بحركة "النطّة" من جديد. */}
          <div key={pathname} className="page-enter">
            {children}
          </div>
        </main>

        <nav
          aria-label="التنقل الرئيسي"
          className="lg:hidden fixed bottom-0 inset-x-0 z-10 bg-white border-t-2 border-line overflow-x-auto pt-2 pb-[max(12px,env(safe-area-inset-bottom))]"
        >
          <div ref={bottomNavRef} className="relative flex min-w-max mx-auto">
            {activeIndex >= 0 && (
              <span
                aria-hidden
                className="nav-pill absolute top-0 h-[52px] rounded-[18px] bg-[#F4E6D3]"
                style={{ width: PILL_WIDTH, right: activeIndex * TAB_WIDTH + (TAB_WIDTH - PILL_WIDTH) / 2 }}
              />
            )}
            {navItems.map((item) => {
              const active = isActive(item.href);
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  prefetch={false}
                  aria-current={active ? "page" : undefined}
                  className={`nav-tab relative flex-none w-[76px] h-[52px] flex flex-col items-center justify-center gap-0.5 text-[11px] ${
                    active ? "text-primary font-extrabold" : "text-ink-soft font-medium"
                  }`}
                >
                  <NavIcon icon={item.icon} />
                  <span className="whitespace-nowrap">{item.label}</span>
                </Link>
              );
            })}
          </div>
        </nav>
      </div>
    </div>
  );
}
