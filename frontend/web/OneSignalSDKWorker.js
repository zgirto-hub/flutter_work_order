importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");

// Set app icon badge when a push arrives (background / app closed)
self.addEventListener('push', function(event) {
  if (!('setAppBadge' in self.navigator)) return;
  event.waitUntil(
    fetch('https://zorin.taila92fe8.ts.net/api/requests/count-open')
      .then(function(r) { return r.json(); })
      .then(function(data) { return self.navigator.setAppBadge(data.count || 0); })
      .catch(function() { return self.navigator.setAppBadge(); })
  );
});
