# Exyte Chat UI Integration Plan for `Sources/Views/ChatView.swift`

## Snapshot
- Current `ChatView` uses a custom `ScrollView`/`ChatBubble` with text-only support bound to `ChatFeature.State`.
- `OpenCodeMessage` already models messages; integration must map these to `ExyteChat.Message` and keep TCA flows intact.
- Sessions workflow (menu, fetch/new session actions) stays in place; only the chat surface and input pipeline change.

## Tasklist
- [x] (P0) Add Exyte Chat package dependency and required products in `Package.swift`, run `swift package resolve`, and confirm `just devcycle` passes without new warnings.
- [x] (P0) Update iOS target Info.plist entries for camera, photo library, and microphone access to unblock media features.
- [x] (P0) Create mapping helpers to convert `OpenCodeMessage` ⇄ `ExyteChat` types (messages, users, attachments, status) and document any unsupported part types.
- [x] (P0) Extend `ChatFeature.State` with computed/cached Exyte message arrays, typing flags, pagination booleans, and media picker state as needed.
- [x] (P0) Expand `ChatFeature.Action`/reducer to handle Exyte callbacks (`sendDraft`, `draftUpdated`, `loadMore`, menu actions, media picker results) while preserving existing API client effects.
- [x] (P0) Replace the legacy `ScrollView` section in `Sources/Views/ChatView.swift` with `ExyteChat.ChatView`, wire the send closure to new actions, and keep the session selector header untouched.
- [x] (P1) Implement custom `messageBuilder`/`inputViewBuilder` to match current bubble styling, integrate error banner/typing indicator via builders, and configure chat theming modifiers.
- [x] (P1) Add pagination trigger via `.enableLoadMore`, typing indicator debouncing, and hook up swipe/menu actions for reply/edit/delete to reducer logic.
- [x] (P1) Support media attachments end-to-end: convert `DraftMessage.attachments` to API payloads, show upload progress/status in UI, and handle failure retries.
- [x] (P1) Surface network/error states inside the chat UI (e.g., `.showNetworkConnectionProblem(true)`, message status updates) and remove redundant overlay UI.
- [ ] (P2) Update unit tests in `FeaturesTests.ChatFeatureTests` for new actions/effects and add mapping helper tests.
- [ ] (P2) Create snapshot/UI tests in `ViewsTests` covering light/dark themes, user vs. assistant messages, attachments, failed sends, and typing indicators.
- [x] (P2) Clean up legacy `ChatBubble` and related helpers once Exyte integration is stable; ensure README/release notes call out new requirements (iOS 17+, permissions).
- [ ] (P2) Plan staged rollout or feature flag if needed, monitor performance (message limits, caching), and gather UX feedback for future enhancements (Giphy, audio).

## Notes & Follow-Up
- Run `just devcycle` before and after major changes; use `just fix`/`just fmt` to resolve lint/style issues automatically.
- Coordinate with backend team on attachment payload expectations and pagination parameters prior to enabling those UI paths.
- Revisit priorities after dependency + core UI swap lands; some P1/P2 tasks may elevate based on release timelines.