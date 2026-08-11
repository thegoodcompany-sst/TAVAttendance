# Android change guide

The root `AGENTS.md` applies here. This file adds Android-specific editing rules.

## Before editing

- Use JDK 17 or 21 and the checked-in Gradle wrapper.
- Copy `secrets.properties.example` to the gitignored `secrets.properties`.
  Never hard-code credentials or commit `google-services.json`.
- Release builds are minified. Serialized or reflectively loaded types may need
  a focused keep rule in `app/proguard-rules.pro`.

## Where changes belong

- Supabase and domain data access: `app/src/main/java/com/example/tavattendance/data/service/`
- Persisted offline mutations: `data/store/`; preserve actor ownership and
  fail-closed decoding/migration behavior
- Models and wire names: `data/models/` with `@Serializable` and `@SerialName`
- Cross-cutting auth/config/error utilities: `core/`
- Compose UI and presentation state: `screens/`; never query Supabase directly
  from a composable
- Pure behavior regressions: `app/src/test/`

Use existing domain data sources or deepen one when appropriate. Do not add a
pass-through repository solely to rename an existing method.

## Verification

Run from this directory:

```bash
./gradlew testDebugUnitTest lintDebug assembleDebug --no-daemon
```

Also exercise a minified release build when changing serialization, Storage,
authentication, or release-only dependencies. Cross-platform file mappings and
handoff conventions live in `PORTING_NOTES.md`.
