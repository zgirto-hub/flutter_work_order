# Quickstart: Optimize iPhone PWA Launch Performance

**Feature**: 009-optimize-pwa-launch  
**Date**: 2026-04-03

## What This Feature Does

Reduces iPhone PWA cold start from ~30 seconds to under 10 seconds through three independent optimizations: server compression, service worker caching, and deferred initialization.

## Implementation Approach (3 Independent Stories)

### US1: Enable Nginx Gzip Compression
1. Add gzip directives to `nginx_flutter_app.conf`
2. Deploy updated config to server
3. **Expected impact**: 65% transfer size reduction (~18 MB → ~6.5 MB)

### US2: Implement Service Worker Caching
1. Replace self-unregistering SW in `deploy_frontend.sh` with a cache-first SW
2. Use `release_id` (already generated) as cache version key
3. SW precaches critical assets on install, serves from cache on fetch
4. **Expected impact**: Repeat launches from cache in < 5 seconds

### US3: Defer Non-Critical Initialization
1. Move OneSignal SDK init to post-Flutter-load
2. Optimize dotenv loading to not block splash screen
3. **Expected impact**: Splash visible within 3 seconds even on slow networks

## Verification Checklist

- [ ] Cold start on iPhone PWA (4G): under 10 seconds
- [ ] Repeat launch (cached): under 5 seconds
- [ ] Splash screen appears within 3 seconds of engine start
- [ ] App update downloads only changed files
- [ ] All features work identically after optimization
- [ ] Push notifications still work (OneSignal)
- [ ] Login/auth still works (Supabase)
- [ ] Works on Android and desktop browsers (no regression)
- [ ] Response headers show gzip/br encoding for assets
- [ ] Service worker is registered and caching assets (DevTools > Application)
