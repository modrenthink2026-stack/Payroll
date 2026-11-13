# Payroll Manager: Android and iPhone/iPad preview

This is a bundled Capacitor application, not a remote website launcher. The web assets ship in the app; live records still require an internet connection and the existing Supabase login and server permissions. No database migration, account grants or live-data changes are made by this build.

## Build

Use Node 22 or newer. From the repository root run `npm ci`, then `cd mobile`, `npm ci`, `npm run platforms`, `npm test`. This generates the Android and iOS projects using pinned Capacitor templates; generated projects and artwork are excluded from Git. Run `npm run android:sync` before opening Android Studio using `npm run android:open`. On a Mac with supported Xcode run `npm run ios:sync`, then `npm run ios:open`. The universal iOS target supports both iPhone and iPad; orientation is not locked. Use a simulator first and synthetic records.

Build identity: `com.modrenthink.payrollmanager`. Confirm ownership/reserve this identifier before store submission. Configure your developer team and signing in Xcode/Android Studio; never commit signing certificates, keystores or passwords. Increment native versionCode/build number for each uploaded build.

## Mobile adaptations

- Bundled mobile builds use the existing HTTPS Supabase project directly, rather than the website-only `/supabase` proxy. Publishable keys are public; RLS and RPC authorization remain authoritative.
- Payroll account-management calls use a narrowly scoped native HTTP adapter that retains the user JWT. Website Origin restrictions and server role checks are unchanged. Other API and blob requests keep normal fetch.
- Recovery emails return to `https://payroll-orpin-one.vercel.app`. Complete password recovery in the browser and sign into the app afterward; existing paste-link verification remains available. Do not add wildcard native redirect URLs or weaken Auth settings.
- CSV/JSON blob exports open the native share/save sheet after an authorized export action. Temporary exports are stored in app cache, removed after sharing, and the export directory is cleaned on the next app launch. No automatic email or messaging occurs.
- Safe-area spacing, touch targets, iPad resizing, connectivity notice and confirmation before Android exit are included. Offline writes/queues are not introduced.
- Native printing and arbitrary popup-window reports have not been implemented. Use the web app for print-only screens until native PDF printing is added. File upload, export/share, recovery, session resumption, all roles and a full monthly workflow need device testing before release.

Payroll retains the existing company and role checks. Staff, HR and Accountant device flows must be tested using synthetic accounts before distribution.

## Release status

This source is a preview, not a claim of signed APK/AAB/IPA or store approval. Android compilation requires the Android SDK; iOS compilation requires macOS/Xcode. Before store submission, replace generated launcher/splash artwork, test authentication and the complete business workflow on actual Android, iPhone and iPad devices, complete privacy disclosures, and configure your developer accounts. Push notifications, biometrics, background work and native printing are outside this initial preview.
