// ~/.mozilla/firefox/<profile>/user.js — XPS 9315 8GB tuning
// Verify each takes effect in about:config after restart.

// Memory: cap content processes (8GB machine; HANDOFF amendment says 2-4, default 8).
user_pref("dom.ipc.processCount", 4);

// VA-API hardware video decode (needs media-libs/libva-intel-media-driver, iHD).
// Check result in about:support -> "Compositing: WebRender" and
// media section of about:support; play a VP9/AV1 video and watch intel_gpu_top.
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("media.hardware-video-decoding.force-enabled", true);

// WebRender on Wayland is default-on for Intel; force only if about:support says otherwise.
// user_pref("gfx.webrender.all", true);

// Stop over-eager commit-space throttling on Linux (~2/3 of RAM).
user_pref("browser.low_commit_space_threshold_mb", 5000);

// Keep default: browser.tabs.unloadOnLowMemory = true
