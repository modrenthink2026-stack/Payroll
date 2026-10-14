# Password recovery

The login screen includes **Forgot password?** and **Have a reset link?**.

1. Select Forgot password, enter your account email and select Send reset email.
2. Check your inbox and spam folder. The response deliberately does not reveal whether an email is registered. Email sending is subject to the shared Supabase email limits; the UI prevents immediate repeated requests.
3. Open the latest reset link. If Supabase redirects to Payroll, the app validates the session and shows the new-password screen.
4. If the link redirects to Project Manager because of the shared Auth redirect settings, return to Payroll and choose Have a reset link. Copy the original unconsumed recovery link from the email and paste it. The app verifies its token with the configured Supabase service through the same-origin proxy. If the link was already consumed, request a new one after the cooldown, or complete the existing recovery screen in Project Manager.
5. Choose and confirm a password of at least 12 characters. After updating it, the recovery session is cleared and the user signs in again.

Payroll and Project Manager share a Supabase account. The new password applies to both. No new password is generated, emailed or stored in GitHub, and the reset feature does not grant or change company roles.

The current tools cannot edit Supabase's Auth redirect allowlist. For direct-click recovery into Payroll, authorize the exact deployed Payroll origin and `/?recovery=1` callback in Authentication → URL Configuration → Redirect URLs. Preserve the construction app's Site URL and existing entries. The paste-link route works independently of that redirect configuration.

Verification: five recovery unit scenarios plus the eight existing tests passed (13 total), and the static build passed. Tests use mocked Auth responses; no actual recovery email was sent or password changed during implementation. Protected deployment access still prevents a real browser/email end-to-end check.
