# Eripoo back-office

Flutter web (NEXT_STEPS C-14). Staff sign in with Supabase Auth and a TOTP
second factor, then use only the `staff_*` functions (migration
`20261023000001_backoffice.sql`). No private project data is reachable,
and the service_role key is never used.

```sh
cd backoffice
flutter pub get && flutter gen-l10n
flutter test
flutter run -d chrome --dart-define-from-file=../env/dev.json
```

Deployment: Actions → **Back-office** → Run workflow (GitHub Pages).
