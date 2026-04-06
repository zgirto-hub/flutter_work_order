# Quickstart: Voice-to-Work-Order Dictation

**Branch**: `022-voice-work-order` | **Date**: 2026-04-06

## Prerequisites

- Flutter SDK 3.x installed
- Chrome browser (for Web Speech API testing)
- Working microphone on your device
- Network connectivity (Web Speech API requires internet)

## Setup

1. **Add dependency** to `frontend/pubspec.yaml`:
   ```yaml
   dependencies:
     speech_to_text: ^7.0.0
   ```

2. **Install packages**:
   ```bash
   cd frontend
   flutter pub get
   ```

3. **Run the app**:
   ```bash
   flutter run -d chrome
   ```

## Testing the Feature

1. Navigate to **Add Work Order** screen (or open an existing work order to edit)
2. Look for the **microphone icon** next to the Title and Description fields
3. Select language (**EN** or **AR**) using the toggle chips
4. Tap the mic button — browser will request microphone permission on first use
5. Speak clearly — transcribed text appears in the field in real-time
6. Tap the mic button again to stop, or wait for silence timeout
7. Edit the transcribed text manually if needed
8. Submit the work order as normal

## Key Files

| File | Purpose |
|------|---------|
| `frontend/lib/widgets/dictation_button.dart` | Mic button widget with recording state |
| `frontend/lib/services/dictation_service.dart` | speech_to_text wrapper (init, start, stop, language) |
| `frontend/lib/screens/Work_Orders/add_work_order.dart` | Modified to include DictationButton on title & description fields |
| `frontend/pubspec.yaml` | New dependency: speech_to_text |

## Browser Compatibility

| Browser | Speech Recognition | Notes |
|---------|-------------------|-------|
| Chrome (Android) | Supported | Primary target — uses Google Speech API |
| Safari (iOS) | Supported | Uses Apple Speech Recognition |
| Firefox | Not supported | Mic button will be hidden |
| Chrome (Desktop) | Supported | For development/testing |

## Troubleshooting

- **Mic button not showing**: Device/browser doesn't support Web Speech API. Test in Chrome.
- **Permission denied**: Clear browser permissions and try again, or check device settings.
- **No transcription**: Check network connectivity. Web Speech API requires internet.
- **Wrong language**: Ensure the correct EN/AR toggle is selected before tapping mic.
