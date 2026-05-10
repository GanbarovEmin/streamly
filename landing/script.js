const releaseUrl = "https://github.com/GanbarovEmin/streamly/releases/latest";
const latestReleaseAPI = "https://api.github.com/repos/GanbarovEmin/streamly/releases/latest";

document.querySelectorAll("[data-download-link]").forEach((link) => {
  link.href = releaseUrl;
});

async function resolveLatestDMG() {
  try {
    const response = await fetch(latestReleaseAPI, {
      headers: { Accept: "application/vnd.github+json" },
      cache: "no-store",
    });

    if (!response.ok) return;

    const release = await response.json();
    const dmgAsset = Array.isArray(release.assets)
      ? release.assets.find((asset) => asset.name && asset.name.endsWith(".dmg") && asset.browser_download_url)
      : null;
    const checksumAsset = Array.isArray(release.assets)
      ? release.assets.find((asset) => asset.name && asset.name.endsWith(".sha256") && asset.browser_download_url)
      : null;

    if (dmgAsset) {
      document.querySelectorAll("[data-download-link]").forEach((link) => {
        link.href = dmgAsset.browser_download_url;
      });
    }

    if (checksumAsset) {
      document.querySelectorAll("[data-checksum-link]").forEach((link) => {
        link.href = checksumAsset.browser_download_url;
        link.hidden = false;
      });
    }
  } catch {
    document.querySelectorAll("[data-download-link]").forEach((link) => {
      link.href = releaseUrl;
    });
  }
}

resolveLatestDMG();

const revealItems = document.querySelectorAll("[data-reveal]");

if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.14 }
  );

  revealItems.forEach((item) => observer.observe(item));
} else {
  revealItems.forEach((item) => item.classList.add("is-visible"));
}
