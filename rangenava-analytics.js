(function () {
  const config = window.RANGENAVA_CONFIG;
  const supabase = window.supabase;

  if (!config || !supabase || !config.anonKey) return;

  const client = supabase.createClient(config.url, config.anonKey);

  // هر بار ورود یا بارگذاری صفحه، یک بازدید جدید ثبت می‌شود.
  async function recordPageView() {
    const { error } = await client
      .from("page_views")
      .insert({
        path: location.pathname
      });

    if (error) {
      console.error("Page view error:", error);
    }
  }

  // شناسه نشست برای آمار بازدیدکنندگان تقریبی
  let sessionId = sessionStorage.getItem("rn_session");

  if (!sessionId) {
    sessionId = crypto.randomUUID();
    sessionStorage.setItem("rn_session", sessionId);
  }

  async function track(eventType, entityType, entityId) {
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
  }

  window.RangenavaAnalytics = { track };

  recordPageView();

  document.addEventListener("click", function (event) {
    const link = event.target.closest("a");
    if (!link) return;

    if (link.hasAttribute("download") ||
        link.dataset.trackDownload === "true") {
      track("download", link.dataset.entityType || "file",
            link.dataset.entityId);
    }

    if (link.dataset.adId) {
      track("ad_click", "advertisement", link.dataset.adId);
    }
  });

  document.querySelectorAll("audio").forEach(function (audio) {
    audio.addEventListener("play", function () {
      track("play", audio.dataset.entityType || "audio",
            audio.dataset.entityId);
    });
  });

  document.querySelectorAll("[data-ad-id]").forEach(function (ad) {
    if (!("IntersectionObserver" in window)) return;

    const observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          track("ad_impression", "advertisement",
                ad.dataset.adId);
          observer.unobserve(entry.target);
        }
      });
    });

    observer.observe(ad);
  });
})();