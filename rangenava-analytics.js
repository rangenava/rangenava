(function () {
  const config = window.RANGENAVA_CONFIG;
  const supabase = window.supabase;

  if (!config || !supabase || !config.anonKey) return;

  const client = supabase.createClient(config.url, config.anonKey);

  let sessionId = sessionStorage.getItem("rn_session");

  if (!sessionId) {
    sessionId = crypto.randomUUID();
    sessionStorage.setItem("rn_session", sessionId);
  }

  async function track(eventType, entityType, entityId) {
    try {
      await client.from("analytics_events").insert({
        event_type: eventType,
        entity_type: entityType || null,
        entity_id: entityId || null,
        path: location.pathname,
        session_id: sessionId
      });
    } catch (error) {
      console.error("Analytics error:", error);
    }
  }

  window.RangenavaAnalytics = { track };

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
          observer.unobserve(ad);
        }
      });
    });

    observer.observe(ad);
  });
})();
