# Research: Voice-to-Work-Order Dictation

**Branch**: `022-voice-work-order` | **Date**: 2026-04-06

## R1: Speech-to-Text Package for Flutter Web (PWA)

**Decision**: Use the `speech_to_text` Flutter package.

**Rationale**: The `speech_to_text` package is the most mature Flutter plugin for speech recognition. It wraps the Web Speech API on web platforms, which is exactly what the PWA needs. It handles microphone permissions, provides real-time partial results, supports language selection via locale codes, and works on both Chrome and Safari mobile browsers. The package abstracts platform differences (Android/iOS/Web) behind a unified Dart API, meaning future native app support would come free.

**Alternatives considered**:
- **Raw Web Speech API via `dart:js_interop`**: Lower-level, more control, but requires manual implementation of permission handling, result parsing, and error recovery. Unnecessary complexity given `speech_to_text` already wraps this cleanly.
- **`flutter_speech`**: Abandoned/unmaintained. No web support.
- **Native platform channels**: Not applicable for PWA target.

## R2: Arabic Speech Recognition Support

**Decision**: Use locale code `ar-SA` (Arabic - Saudi Arabia) for Arabic and `en-US` for English via the `speech_to_text` package's `localeId` parameter.

**Rationale**: The Web Speech API (which `speech_to_text` delegates to on web) supports Arabic via Google's speech recognition service in Chrome. Safari uses Apple's speech recognition which also supports Arabic. The `ar-SA` locale provides the best coverage for Gulf Arabic speakers. The language is selected explicitly by the user via a toggle (EN/AR chips), matching the existing pattern in `AiInsightsCard`.

**Alternatives considered**:
- **Auto-detect language from speech**: Unreliable for short utterances and not supported by the Web Speech API's `continuous` mode. Users must select language explicitly.
- **`ar` (generic Arabic)**: Works but `ar-SA` provides better recognition accuracy for the target user base.

## R3: Microphone Permissions on PWA

**Decision**: Request microphone permission at the moment the user taps the mic button (just-in-time). Handle denial with an inline message.

**Rationale**: The `speech_to_text` package's `initialize()` method triggers the browser's permission prompt automatically. If the user denies permission, the package returns a status that can be checked. No upfront permission request on page load is needed — just-in-time is the standard UX pattern for PWAs and avoids permission fatigue.

**Alternatives considered**:
- **Request permission on screen load**: Aggressive; users may deny reflexively before understanding why it's needed.
- **Separate permission settings page**: Over-engineered for a single permission.

## R4: Architecture — Widget vs Service Split

**Decision**: Create a `DictationButton` widget and a `DictationService` service class.

**Rationale**:
- **`DictationService`** (`frontend/lib/services/dictation_service.dart`): Manages the `speech_to_text` plugin lifecycle — initialization, start/stop listening, language selection, availability checking. Singleton pattern (consistent with existing services like `WorkOrderService`). Encapsulates platform-specific concerns.
- **`DictationButton`** (`frontend/lib/widgets/dictation_button.dart`): A stateful widget that renders the microphone icon button, manages visual recording state (idle/recording), and calls `DictationService` methods. Accepts a `TextEditingController` and appends transcribed text to it. Accepts a `language` parameter (`en` or `ar`).

This split keeps the `AddWorkOrderScreen` changes minimal — just swap two `TextFormField` widgets to include a `DictationButton` in their `suffixIcon` or as an adjacent button.

**Alternatives considered**:
- **Inline all logic in AddWorkOrderScreen**: Would bloat an already large screen file (~1600 lines). Violates separation of concerns.
- **Mixin approach**: Unusual pattern in this codebase; services and widgets are the established pattern.

## R5: Language Toggle UX

**Decision**: Add EN/AR toggle chips near the mic button area, matching the pattern used in `AiInsightsCard` (`_buildLanguageChip`).

**Rationale**: The app has no global language/locale setting. The AI Insights feature (021) already established a per-widget EN/AR chip toggle pattern that users are familiar with. Reusing this pattern provides consistency. The language selection applies to dictation only — it determines which `localeId` is passed to the speech recognizer.

**Alternatives considered**:
- **Global app locale setting**: Would require adding a localization framework (intl/easy_localization) — far beyond the scope of this feature.
- **Auto-detect from device locale**: Unreliable; many bilingual users have their device in English but speak Arabic, or vice versa.
- **No toggle (always use device locale)**: Same problem as auto-detect.

## R6: Network Connectivity Handling

**Decision**: Detect speech recognition failure due to network issues and show an inline SnackBar message guiding users to type instead.

**Rationale**: The Web Speech API requires network connectivity (audio is sent to Google/Apple servers for processing). The `speech_to_text` package reports errors via its `onError` callback, including network-related failures. A simple SnackBar with a message like "Speech recognition unavailable — please type instead" is consistent with existing error patterns in the app (e.g., line 1339 in `add_work_order.dart`).

**Alternatives considered**:
- **Disable mic button when offline**: Requires continuous network monitoring; over-engineered. The error callback already handles this case.
- **Offline speech recognition**: Not supported by Web Speech API. Would require a completely different approach (on-device models), which is far beyond scope.
