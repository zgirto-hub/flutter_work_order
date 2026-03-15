importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");

// Set app icon badge when a push arrives (background / app closed)
self.addEventListener('push', function(event) {
  if ('setAppBadge' in self.navigator) {
    event.waitUntil(
      self.navigator.setAppBadge().catch(function() {})
    );
  }
});
