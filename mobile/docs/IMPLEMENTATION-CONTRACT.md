# ConsegVida mobile — implementation contract

Date: 2026-10-29. Baseline: `94aef07fb12c852b7f555d5f5f5f51827b78de8e`.

## Product boundary

ConsegVida is the human-development manifesto in this repository. Preserve Fase 1 — Despertar and the physical, mental and spiritual axes. This is not the brokerage app and not Hero-mindset. No insurance quotes, XP, guilds, rankings, invented phases, paid AI, ads, remote accounts or CRM connectors in this first mobile slice.

The requested xtool is the CLI at https://github.com/xtool-org/xtool. Use it for the SwiftUI iOS development project. It does not target Android. A separate native Android client uses the same bundled content. Generating a development app is distinct from store distribution.

## First functional slice

1. PT-BR home with the three axes, canonical philosophy and Fase 1.
2. One practical mission per axis, derived from the committed philosophy. A user can select/start a mission, complete it and see real completion history.
3. State survives application restarts, stored only in the application sandbox. No network transmission, account, tracking or cloud synchronization. Explicit user action may open the original manifesto in the external browser.
4. A completion is idempotent per mission per local calendar date. Counts do not invent streaks or impact. No future date accepted by application operations.
5. Invalid state must produce a visible recovery choice; never silently claim successful saving, and never automatically erase corrupt or unknown-version state.
6. User can erase local progress after an explicit confirmation in the app. Reset removes active and completed state.
7. Local-day strings are Gregorian `YYYY-MM-DD`, using the device time zone; identifiers are one of the bundled mission IDs.
8. Accessibility: semantic controls, scalable text, readable contrast and platform back navigation. No compulsory motion or permissions.

## Shared content

Source: `mobile/shared/content.json`; generated platform copies must match it. Existing `src/data/philosophy.json`, `src/styles/tokens.css` and `public/favicon.svg` are canonical inputs and remain intact. Mission instructions below are a product adaptation of the source, not quotations from the manifesto.

## State contract v1

```json
{"version":1,"activeMission":null,"completions":[{"missionId":"fisico-entorno","completedOn":"2026-10-29"}]}
```

Mission IDs: `fisico-entorno`, `mental-foco`, `espiritual-presenca`. Store no names, email addresses, health information, freeform journal or credentials. Reject malformed dates, unknown mission IDs, duplicate completion keys and unsupported versions on decode; cap imported file size and record count. There is no import UI in v1.

## Verification seams

- Domain operations: start, complete, duplicate prevention, local date validation, history and reset.
- Persistence: encode/decode, actual file write/reload, corruption and write failure.
- Content contract: same mission IDs, canonical axes/colors and bundle parity on both clients.
- Android: compile native APK, verify signing/permissions; device test only when available.
- iOS: Swift core tests, SwiftUI build where Apple SDK exists, xtool scaffold/CLI validation; hardware signing only with authorized account/device.
- Store publication: only confirmed after actual submission and storefront status. Do not label source code, unsigned builds, development signatures or CI checks as a store launch.

## Release boundaries

Use provisional package/bundle ID `com.consegvida.app` until developer-account availability is checked. Version `0.1.0`, build `1`. No store purchase, credential creation, signing secret in source, production backend mutation, or assertion of store acceptance. Read-only account availability can be inspected. Prepare documentation and reviewable code before requesting any missing account action.
