(function () {
"use strict";

const config = window.RANGENAVA_CONFIG;
const supabase = window.supabase;

if (!config || !supabase || !config.anonKey) return;

const client = supabase.createClient(
config.url,
config.anonKey
);

let sessionId = sessionStorage.getItem("rn_session");

if (!sessionId) {
sessionId = crypto.randomUUID();
sessionStorage.setItem("rn_session", sessionId);
}

let pageViewTimer = null;
let lastPageViewAt = 0;
let pageViewInFlight = false;

async function recordPageView() {
const now = Date.now();

// جلوگیری از ثبت بازدید تکراری
if (
  pageViewInFlight ||
  now - lastPageViewAt < 2000
) {
  return;
}

lastPageViewAt = now;
pageViewInFlight = true;

try {
  const { error } = await client
    .from("page_views")
    .insert({
      path: location.pathname
    });

  if (error) {
    console.error("Page view error:", error);
  }
} catch (error) {
  console.error("Page view error:", error);
} finally {
  pageViewInFlight = false;
}

}

function schedulePageView() {
clearTimeout(pageViewTimer);

pageViewTimer = setTimeout(function () {
  if (document.visibilityState === "visible") {
    recordPageView();
  }
}, 400);

}

let wasHidden = false;

// ثبت بازدید هنگام ورود اولیه
schedulePageView();

// ثبت بازدید هنگام بازگشت به صفحه
document.addEventListener("visibilitychange", function () {
if (document.visibilityState === "hidden") {
wasHidden = true;
return;
}

if (wasHidden) {
  wasHidden = false;
  schedulePageView();
}

});

// مدیریت بازگشت از حافظه موقت مرورگر
window.addEventListener("pageshow", function (event) {
if (event.persisted) {
schedulePageView();
}
});

async function track(eventType, entityType, entityId) {
try {
const { error } = await client
.from("analytics_events")
.insert({
event_type: eventType,
entity_type: entityType || null,
entity_id: entityId || null,
path: location.pathname,
session_id: sessionId
});

  if (error) {
    console.error("Analytics error:", error);
  }
} catch (error) {
  console.error("Analytics error:", error);
}

}

window.RangenavaAnalytics = {
track: track,
recordPageView: recordPageView
};

// ثبت کلیک‌ها و دانلودها
document.addEventListener("click", function (event) {
const target = event.target;

if (!target || typeof target.closest !== "function") {
  return;
}

const link = target.closest("a");

if (!link) return;

if (
  link.hasAttribute("download") ||
  link.dataset.trackDownload === "true"
) {
  track(
    "download",
    link.dataset.entityType || "file",
    link.dataset.entityId
  );
}

if (link.dataset.adId) {
  track(
    "ad_click",
    "advertisement",
    link.dataset.adId
  );
}

});

// ثبت پخش فایل‌های صوتی
document.querySelectorAll("audio").forEach(function (audio) {
audio.addEventListener("play", function () {
track(
"play",
audio.dataset.entityType || "audio",
audio.dataset.entityId
);
});
});

// ثبت مشاهده تبلیغات
document.querySelectorAll("[data-ad-id]").forEach(function (ad) {
if (!("IntersectionObserver" in window)) return;

const observer = new IntersectionObserver(function (entries) {
  entries.forEach(function (entry) {
    if (entry.isIntersecting) {
      track(
        "ad_impression",
        "advertisement",
        ad.dataset.adId
      );

      observer.unobserve(entry.target);
    }
  });
});

observer.observe(ad);

});

})();