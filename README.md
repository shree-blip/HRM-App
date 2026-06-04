# Focus HRM — Flutter (iOS & Android)

Mobile rebuild of the Focus HRM web app. It uses the **same Supabase backend**
as the existing React app — no schema or backend changes.

> **Status:** Phase 0 (foundation) + Phase 1 (authentication) complete.
> Dashboard, employees, attendance, leave, approvals, reports and payroll
> follow in later phases.

## Stack

| Concern            | Choice                                   |
| ------------------ | ---------------------------------------- |
| State management   | Riverpod (`flutter_riverpod`)            |
| Routing            | `go_router`                              |
| Backend            | `supabase_flutter` (same project)        |
| Secure session     | `flutter_secure_storage` (encrypted)     |
| Form validation    | `form_builder_validators`                |
| Config             | `flutter_dotenv` (`.env`, gitignored)    |

## First-time setup

This repo currently contains the Dart source, config, and assets — but **not**
the native platform folders (`android/`, `ios/`), because Flutter isn't
installed in the authoring environment. Generate them once after installing
Flutter:

```bash
# 1. Install Flutter SDK: https://docs.flutter.dev/get-started/install
flutter --version          # confirm it's on PATH

# 2. From the project root, generate the native platform scaffolding.
#    This adds android/ ios/ etc. WITHOUT deleting lib/ source.
cd hrm-focus-flutter
flutter create --org com.focusyourfinance --project-name hrm_focus_flutter --platforms=android,ios .

# 3. If `flutter create` regenerated any of our managed files
#    (pubspec.yaml, analysis_options.yaml, .gitignore, lib/main.dart, README.md),
#    restore our versions — they were committed before this step:
git checkout -- pubspec.yaml analysis_options.yaml .gitignore lib/main.dart README.md

# 4. Install dependencies and run.
flutter pub get
flutter run            # with an emulator/device connected
```

> The `.env` file already contains the Supabase URL + anon key (copied from the
> React app's `.env`). It is gitignored. Only the **publishable/anon** key is
> used — never the `service_role` key.

## Project structure

```
lib/
├── main.dart                       # bootstrap: load env, init Supabase, runApp
├── app/
│   ├── app.dart                    # MaterialApp.router
│   ├── router.dart                 # GoRouter + auth-aware redirects
│   └── theme/app_theme.dart        # brand teal theme (ported from CSS vars)
├── core/
│   ├── config/env.dart             # typed .env access
│   ├── supabase/                   # client init + encrypted session storage
│   ├── auth/                       # repository, controller, state
│   ├── permissions/                # Permission enum + effective-perm controller
│   ├── models/                     # Profile, AppRole
│   ├── validation/validators.dart  # mirrors React Zod rules
│   └── widgets/                    # shared widgets
└── features/
    ├── auth/presentation/          # login/signup + forgot-password screens
    └── dashboard/presentation/     # Phase-1 placeholder home
```

## What works in Phase 1

- Email/password login, allowlist-gated signup, forgot password
- Deactivated-account and not-allowlisted handling
- Role + line-manager resolution, effective permissions (role + overrides)
  with realtime sync
- Encrypted session persistence; auto-redirect based on auth state
