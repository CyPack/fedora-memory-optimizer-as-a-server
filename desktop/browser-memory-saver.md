# Browser Memory Saver — tier-1 of the desktop OOM ladder

The gentlest tier: let the browser **unload idle tabs** under memory pressure *before* any
OOM kill is needed. A discarded tab drops to ~0 RAM (its renderer process is terminated);
clicking it reloads. This is the desktop analogue of macOS "App Nap" / memory compression.

These are **UI / profile settings** — they cannot be scripted system-wide, so apply per browser.

## 🦁 Brave / Chromium / Edge (Chromium 116+)

`Settings → System → Memory` (or `brave://settings/system`):

- **Memory Saver = ON**
- Aggressiveness = **Maximum** (tabs become inactive after a *shorter* idle period)
- **Always keep these sites active** → add anything you never want discarded
  (e.g. `web.whatsapp.com`, a dashboard, a long-running web app)

> Note: in recent Chromium the old `chrome://flags/#heuristic-memory-saver-mode` flag was
> **removed** — the control lives in Settings now. Manual/test discard + live state:
> `brave://discards` (or `chrome://discards`) → "Urgent Discard".

## 🦊 Firefox (`about:config` or drop a `user.js` in the profile)

Firefox already manages **per-tab** `oom_score_adj` itself (foreground low, background high),
which is smarter than a blanket value — so the OOM ladder daemon deliberately leaves Firefox
content processes alone and only protects the Firefox **main** process. Add aggressive
unloading on top:

```ini
// Tab unloading (Memory Saver equivalent)
user_pref("browser.tabs.unloadOnLowMemory", true);              // unload idle tabs under pressure (Linux: enable)
user_pref("browser.low_commit_space_threshold_percent", 20);    // trigger unload earlier (default 5)
user_pref("browser.tabs.min_inactive_duration_before_unload", 300000);  // 10min → 5min idle before eligible
// Bonus: cut disk I/O churn (session is written to disk less often)
user_pref("browser.sessionstore.interval", 60000);             // 15s → 60s
```

`about:unloads` shows the LRU unload order and lets you unload tabs manually. Pinned tabs,
tabs playing audio, and tabs using WebRTC are never auto-unloaded.

## Why this is tier-1

```
Tier 1  browser memory-saver  → discard idle tabs (no kill, instant reload)   ← THIS doc
Tier 2  oom-browser-ladder + earlyoom → kill ONE renderer (tab) under real pressure
Tier 3  (last resort) kernel OOM with renderer-weighted oom_score → still a tab, not the app
```

The browser main process and its GPU/network helpers stay protected at every tier, so you
never lose the whole browser (and all your tabs) when a single tab would have been enough.
