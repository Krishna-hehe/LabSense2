# HIPAA Compliance Roadmap for LabSense2

Ensuring HIPAA compliance involves Technical Safeguards, Physical Safeguards, and Administrative Safeguards. Since LabSense2 handles PHI (Protected Health Information) via Lab Results, high security is mandatory.

## 1. Technical Safeguards (Code & Infrastructure)

### A. Authentication & Access Control

- [ ] **MFA (Multi-Factor Authentication)**: Enable 2FA in Supabase Auth settings to add a layer beyond just email/password.
- [ ] **Biometric Enforcement**: Make biometric login mandatory for quick access (currently optional).
- [ ] **Automatic Logoff**: Implement an inactivity timer that logs the user out or locks the screen after 5-10 minutes of inactivity.
  - *Requirement*: § 164.312(a)(2)(iii)

### B. Encryption (At Rest & In Transit)

- [ ] **Local Storage**: Replace standard `SharedPreferences` (which is not encrypted on all devices) with `flutter_secure_storage` for storing tokens, user IDs, and cached health data.
- [ ] **Database**: Ensure Supabase "Project Level" encryption is active.
- [ ] **Transmission**: Verify all API calls use TLS 1.2+ (HTTPS). (Already handled by standard Flutter/Supabase libraries).

### C. Audit Controls

- [ ] **Access Logs**: Create a `access_logs` table in Supabase to track *who* viewed *what* record and *when*.
- [ ] **Immutable Logs**: Ensure these logs cannot be deleted by standard users.

### D. App Privacy

- [ ] **Screen Security**: Prevent the OS from taking screenshots of the app in the "Recent Apps" switcher.
  - *Implementation*: Use `flutter_windowmanager` (Android) to set `FLAG_SECURE`.
- [ ] **Sanitized Logging**: Ensure `debugPrint` or `print` statements containing PII are strictly removed in Release builds.

## 2. AI & Third-Party Processors

### A. Business Associate Agreements (BAA)

- [ ] **Supabase**: You must be on the **Team/Enterprise Plan** to sign a BAA. Free tier is NOT HIPAA compliant.
- [ ] **Google Cloud (NIM)**: Consumer API keys (AI Studio) are generally NOT HIPAA compliant. You must use **Vertex AI on Google Cloud** and enable the appropriate compliance settings.

### B. Data Minimization

- [ ] **Anonymization**: Before sending data to the AI, strip patient names/DOB if the "Analysis" feature doesn't strictly require them.
- [ ] **Stateless Usage**: Ensure the AI provider is configured for "Zero Data Retention" (they do not train on your API data).

## 3. Administrative Actions

- [ ] **Privacy Policy**: Update to explicitly state how PHI is handled.
- [ ] **Risk Assessment**: Document potential risks (e.g., what if a phone is stolen?).

---

## Recommended Immediate Code Changes

1. **Implement Auto-Logout Service**: Wrap the application in a `Listener` that tracks touch events and resets a timer.
2. **Secure Local Storage**: Migration utility to move `SharedPreferences` data to `FlutterSecureStorage`.

