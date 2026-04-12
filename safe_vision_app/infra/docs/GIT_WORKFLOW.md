# SafeVision — Git & Team Workflow

## Branch Strategy: GitFlow

```
main          ← production releases (tag: v1.x.x)
  ↑
develop       ← integration branch, always deployable to staging
  ↑
feature/*     ← new features (branched from develop)
fix/*         ← bug fixes (branched from develop)
hotfix/*      ← urgent production fixes (branched from main)
release/*     ← release preparation (branched from develop)
```

## Branch Naming Convention

```
feature/SV-XXX-short-description
fix/SV-XXX-short-description
hotfix/SV-XXX-short-description
release/v1.2.0
```

**Examples:**
```
fix/SV-001-tts-double-enqueue
fix/SV-002-isolate-busy-reset
feature/SV-050-object-history-log
hotfix/SV-099-crash-on-camera-switch
release/v1.1.0
```

## Commit Convention (Conventional Commits)

Format: `type(scope): description`

### Types

| Type       | When to use |
|------------|-------------|
| `feat`     | New feature |
| `fix`      | Bug fix |
| `perf`     | Performance improvement |
| `refactor` | Refactor with no behaviour change |
| `test`     | Add or update tests |
| `docs`     | Documentation only |
| `chore`    | Build system, CI, dependency updates |
| `style`    | Formatting, whitespace (no logic change) |

### Scopes

`tts` | `detection` | `camera` | `settings` | `ui` | `di` | `ci` | `model`

### Example commit messages

```
fix(tts): remove double enqueue in speakWarning (SV-001)
fix(detection): reset _isolateBusy in finally block (SV-002)
fix(detection): add CloseModelUsecase per clean architecture (SV-007)
feat(detection): use frame locking via onDone callback (SV-009)
perf(ui): use version counter in BoundingBoxPainter.shouldRepaint (SV-011)
test(tts): add unit tests for cooldown logic in speakWarning
chore(ci): switch Flutter pin to stable channel
fix(settings): forward speechRate when changing TTS language (SV-006)
```

### Breaking Changes

Add `!` after the scope and include a `BREAKING CHANGE` section in the body:

```
feat(detection)!: replace DetectionRepository injection with CloseModelUsecase

BREAKING CHANGE: DetectionBloc constructor no longer accepts a repository parameter.
Use closeModel: CloseModelUsecase instead.
```

## PR Checklist

Copy into the PR description:

```markdown
## Description
<!-- Briefly describe what was changed -->

Closes #XXX

## Type of change
- [ ] Bug fix (SV-XXX)
- [ ] New feature
- [ ] Performance improvement
- [ ] Refactoring
- [ ] Documentation

## Testing
- [ ] Unit tests added/updated
- [ ] Widget tests added/updated
- [ ] Tested on Android (physical device or emulator)
- [ ] Tested on iOS (physical device or simulator)
- [ ] All existing tests pass (`flutter test`)

## Code Quality
- [ ] `flutter analyze` passes with no issues
- [ ] `dart format` has been applied
- [ ] No hardcoded strings (use constants)
- [ ] No `print()` calls (use `debugPrint()` guarded by `kDebugMode`)

## Review Notes
<!-- Points that need special attention from the reviewer -->
```

## Local Development Setup

```bash
# Clone and set up
git clone https://github.com/your-org/safe_vision_app.git
cd safe_vision_app
flutter pub get

# Run all tests
flutter test

# Run a specific test file
flutter test test/features/tts/tts_service_fix_test.dart

# Run tests with a coverage report
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html

# Format code
dart format lib/ test/

# Analyze
flutter analyze --fatal-infos
```

### Simulating CI locally with Docker

```bash
# Analyze
docker compose -f infra/docker/docker-compose.yml run analyze

# Full test suite
docker compose -f infra/docker/docker-compose.yml run test

# Specific test file
docker compose -f infra/docker/docker-compose.yml run test-file \
  test/features/tts/tts_service_fix_test.dart

# Build debug APK
docker compose -f infra/docker/docker-compose.yml run build-android
```

## Semantic Versioning

```
v{MAJOR}.{MINOR}.{PATCH}+{BUILD}

MAJOR : Breaking API changes
MINOR : New features (backward compatible)
PATCH : Bug fixes
BUILD : Auto-incremented by CI
```

Example in `pubspec.yaml`:
```yaml
version: 1.2.3+47
```

## CI/CD Overview

The pipeline runs automatically on every push and PR:

```
push/PR
  └─► analyze (lint + format)
        └─► test (unit + widget, coverage ≥ 80%)
              ├─► build-android (debug + release)
              └─► build-ios (no-codesign)
                    └─► release (main only, after all jobs pass)
```

A Slack notification is sent to `#safevision-alerts` whenever a job fails.
Full configuration is in `.github/workflows/ci.yml`.