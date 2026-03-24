# Security Integration Phase 2-3 - Implementation Plan

**Project:** LabSense2 Health Management Platform  
**Task:** Integrate Input Validation, Rate Limiting, CSP Headers & Security Monitoring Dashboard  
**Created:** 2026-01-31  
**Status:** 🟡 Planning Complete - Awaiting Implementation

---

## 📋 Overview

### What & Why

This plan implements the remaining Phase 2-3 security features to achieve the target security score of 85/100. The integration focuses on:

1. **Input Validation Integration** - Prevent SQL injection and XSS attacks
2. **Rate Limiting Integration** - Protect against brute force and DoS attacks
3. **CSP Headers** - Prevent XSS and code injection in web platform
4. **Security Monitoring Dashboard** - Real-time security metrics and alerts

### Success Criteria

| Metric | Current | Target | Verification |
| :--- | :--- | :--- | :--- |
| **Security Score** | 65/100 | 85/100 | Security audit script |
| **Input Validation Coverage** | 0% | 100% | All user inputs validated |
| **Rate Limiting Coverage** | 0% | 100% | Login, uploads, AI queries protected |
| **CSP Implementation** | ❌ None | ✅ Strict | Web CSP headers active |
| **Security Dashboard** | ❌ None | ✅ Live | Real-time metrics visible |

---

## 🏗️ Project Type

**Platform:** Flutter Multi-Platform (Web, iOS, Android)  
**Primary Agent:** `mobile-developer` (Flutter full-stack)  
**Supporting Agents:** `security-auditor`, `backend-specialist`, `test-engineer`

---

## 🛠️ Tech Stack

| Component | Technology | Rationale |
| :--- | :--- | :--- |
| **Framework** | Flutter 3.x | Existing platform |
| **Backend** | Supabase | Existing infrastructure |
| **State Management** | Riverpod 2.5.1 | Existing pattern |
| **Security Services** | Custom Dart services | Already created, need integration |
| **CSP** | Meta tags (Web) | Standard web security |
| **Monitoring** | Custom dashboard + Sentry | Real-time + error tracking |

---

## 📁 File Structure

### Existing Files (To Modify)

```text
lib/
├── main.dart                                    # Add RLS verification on auth
├── core/
│   ├── ai_service.dart                         # Add rate limiting to AI queries
│   ├── supabase_service.dart                   # Add input validation to DB ops
│   └── services/
│       ├── rls_verification_service.dart       # ✅ Already exists
│       ├── rate_limiter.dart                   # ✅ Already exists
│       ├── input_validation_service.dart       # ✅ Already exists
│       └── upload_service.dart                 # Add rate limiting to uploads
├── features/
│   ├── auth/
│   │   └── login_page.dart                     # Add rate limiting + validation
│   └── settings/
│       └── settings_page.dart                  # Add profile validation
└── widgets/
    └── (new) security_dashboard_widget.dart    # NEW: Security metrics widget

web/
└── index.html                                   # Add CSP meta tags

test/
└── security/
    ├── input_validation_test.dart              # NEW: Validation tests
    ├── rate_limiter_test.dart                  # NEW: Rate limit tests
    └── security_integration_test.dart          # NEW: E2E security tests
```

### New Files (To Create)

```text
lib/
├── features/
│   └── security/
│       ├── security_dashboard_page.dart        # NEW: Full security dashboard
│       └── widgets/
│           ├── rate_limit_monitor.dart         # NEW: Rate limit stats
│           ├── rls_status_card.dart            # NEW: RLS verification status
│           ├── security_score_gauge.dart       # NEW: Visual security score
│           └── recent_security_events.dart     # NEW: Security event log

docs/
└── SECURITY_INTEGRATION_PROGRESS.md            # NEW: Track integration status
```

---

## 📝 Task Breakdown

### PHASE 2A: Input Validation Integration (TDD First) (Priority: P0)

#### Task 2A.0: Create Validation Unit Tests (TDD)

- **Agent:** `test-engineer`
- **Skill:** `tdd-workflow`, `testing-patterns`
- **Priority:** P0 (Critical)
- **Dependencies:** None
- **Estimated Time:** 15 minutes

**INPUT:**

- `test/security/input_validation_test.dart` (Create new)
- Validation rules requirements

**OUTPUT:**

- Failing tests for: email format, password complexity, SQL injection patterns, XSS patterns
- Test suite ready for implementation cycle

**VERIFY:**

```bash
flutter test test/security/input_validation_test.dart
# Expected: All tests FAIL (Red phase)
```

---

#### Task 2A.1: Implement Input Validation in Login

- **Agent:** `mobile-developer`
- **Skill:** `clean-code`, `vulnerability-scanner`
- **Priority:** P0 (Critical)
- **Dependencies:** None
- **Estimated Time:** 15 minutes

**INPUT:**

- Existing `login_page.dart`
- Existing `input_validation_service.dart`

**OUTPUT:**

- Email validation before authentication
- Password strength validation for signup
- Sanitized inputs to prevent XSS

**VERIFY:**

```bash
# Test invalid email
# Expected: Error message "Invalid email format"

# Test weak password on signup
# Expected: Error message with requirements

# Test SQL injection pattern in email
# Expected: Blocked with security error
```

---

#### Task 2A.2: Integrate Input Validation in Database Operations

- **Agent:** `mobile-developer`
- **Skill:** `clean-code`, `vulnerability-scanner`
- **Priority:** P0 (Critical)
- **Dependencies:** Task 2A.1
- **Estimated Time:** 20 minutes

**INPUT:**

- Existing `supabase_service.dart`
- Existing `input_validation_service.dart`

**OUTPUT:**

- Sanitized lab result names
- Validated profile updates (name, email, phone)
- SQL injection detection on all text inputs

**VERIFY:**

```bash
# Try to insert lab result with SQL injection pattern
# Expected: Blocked with "Invalid input detected"

# Update profile with XSS pattern in name
# Expected: Sanitized to safe text only
```

---

#### Task 2A.3: Integrate Input Validation in Settings

- **Agent:** `mobile-developer`
- **Skill:** `clean-code`
- **Priority:** P1 (High)
- **Dependencies:** Task 2A.2
- **Estimated Time:** 10 minutes

**INPUT:**

- Existing `settings_page.dart`
- Existing `input_validation_service.dart`

**OUTPUT:**

- Name field validation (letters, spaces, hyphens only)
- Phone number validation
- Email validation on profile updates

**VERIFY:**

```bash
# Enter invalid characters in name field
# Expected: Sanitized to valid characters only

# Enter invalid phone format
# Expected: Error message with format guidance
```

---

### PHASE 2B: Rate Limiting Integration (TDD & Configurable) (Priority: P0)

#### Task 2B.0: Create Rate Limiter Unit Tests (TDD)

- **Agent:** `test-engineer`
- **Skill:** `tdd-workflow`
- **Priority:** P0 (Critical)
- **Dependencies:** None
- **Estimated Time:** 15 minutes

**INPUT:**

- `test/security/rate_limiter_test.dart` (Create new)

**OUTPUT:**

- Tests for: token bucket logic, lockout timing, limit enforcement
- Tests for configuration loading

**VERIFY:**

```bash
flutter test test/security/rate_limiter_test.dart
# Expected: All tests FAIL (Red phase)
```

---

#### Task 2B.1: Integrate Configurable Rate Limiting in Login

- **Agent:** `mobile-developer`
- **Skill:** `clean-code`, `vulnerability-scanner`
- **Priority:** P0 (Critical)
- **Dependencies:** Task 2A.1
- **Estimated Time:** 20 minutes

**INPUT:**

- Modified `login_page.dart` (from 2A.1)
- Existing `rate_limiter.dart`

**OUTPUT:**

- Login attempts limited to 5 per 15 minutes
- 30-minute lockout after limit exceeded
- Success resets the counter
- Clear error messages with time remaining

**VERIFY:**

```bash
# Attempt login with wrong password 6 times
# Expected: 
# - Attempts 1-5: "Invalid credentials"
# - Attempt 6: "Too many failed attempts. Try again in 30 minutes."

# Successful login after 3 failed attempts
# Expected: Counter resets
```

---

#### Task 2B.2: Integrate Rate Limiting in File Uploads

- **Agent:** `mobile-developer`
- **Skill:** `clean-code`
- **Priority:** P0 (Critical)
- **Dependencies:** None
- **Estimated Time:** 15 minutes

**INPUT:**

- Existing `upload_service.dart`
- Existing `rate_limiter.dart`

**OUTPUT:**

- File uploads limited to 10 per 5 minutes
- Clear error message when limit reached
- User ID-based tracking

**VERIFY:**

```bash
# Upload 11 files rapidly
# Expected: 
# - Files 1-10: Success
# - File 11: "Upload limit reached. 0 uploads remaining."
```

---

#### Task 2B.3: Integrate Rate Limiting in AI Queries

- **Agent:** `mobile-developer`
- **Skill:** `clean-code`
- **Priority:** P0 (Critical)
- **Dependencies:** None
- **Estimated Time:** 15 minutes

**INPUT:**

- Existing `ai_service.dart`
- Existing `rate_limiter.dart`

**OUTPUT:**

- AI queries limited to 20 per 5 minutes
- Clear error message when limit reached
- User ID-based tracking

**VERIFY:**

```bash
# Make 21 AI analysis requests rapidly
# Expected:
# - Requests 1-20: Success
# - Request 21: "AI query limit reached. 0 queries remaining."
```

---

### PHASE 2C: RLS Verification Integration (Priority: P0)

#### Task 2C.1: Initialize RLS Verification on App Start

- **Agent:** `mobile-developer`
- **Skill:** `clean-code`, `vulnerability-scanner`
- **Priority:** P0 (Critical)
- **Dependencies:** None
- **Estimated Time:** 10 minutes

**INPUT:**

- Existing `main.dart`
- Existing `rls_verification_service.dart`

**OUTPUT:**

- RLS verification runs on user authentication
- Security logs show verification status
- Critical alert if RLS fails

**VERIFY:**

```bash
# Login to app
# Expected console logs:
# "🔐 User authenticated - verifying RLS policies..."
# "✅ RLS verification passed for all tables"

# Check Sentry for any RLS failure alerts
# Expected: No critical alerts
```

---

#### Task 2C.2: Implement Error Recovery & Fallbacks

- **Agent:** `mobile-developer`
- **Skill:** `clean-code`
- **Priority:** P1 (High)
- **Dependencies:** Task 2C.1
- **Estimated Time:** 20 minutes

**INPUT:**

- `rls_verification_service.dart`

**OUTPUT:**

- Graceful degradation: If RLS check fails, force logout or strictly limit access.
- User-friendly error messages for security blocks.
- Retry mechanism for transient verification failures.

**VERIFY:**

```bash
# Simulate RLS check failure (mock network error)
# Expected: App shows "Security Verification Failed - Retrying..." then logs out if persistent.
```

---

### PHASE 3A: CSP Headers (Web Only) (Priority: P1)

#### Task 3A.1: Add CSP Meta Tags to Web Index

- **Agent:** `mobile-developer`
- **Skill:** `vulnerability-scanner`
- **Priority:** P1 (High)
- **Dependencies:** None
- **Estimated Time:** 10 minutes

**INPUT:**

- Existing `web/index.html`

**OUTPUT:**

- Strict CSP meta tags
- Allow only trusted sources (Supabase, Google Fonts, NVIDIA NIM API)
- Block inline scripts and eval()

**VERIFY:**

```bash
# Run web app in Chrome
# Open DevTools → Console
# Expected: No CSP violation errors

# Try to inject inline script via browser console
# Expected: Blocked by CSP
```

**CSP Policy:**

```html
<meta http-equiv="Content-Security-Policy" content="
  default-src 'self';
  script-src 'self' 'wasm-unsafe-eval';
  style-src 'self' 'unsafe-inline' https://fonts.googleapis.com;
  font-src 'self' https://fonts.gstatic.com;
  img-src 'self' data: https://*.supabase.co;
  connect-src 'self' https://*.supabase.co https://integrate.api.nvidia.com;
  frame-ancestors 'none';
  base-uri 'self';
  form-action 'self';
">
```

---

### PHASE 3B: Security Monitoring Dashboard (Priority: P2)

#### Task 3B.1: Create Security Dashboard Page

- **Agent:** `mobile-developer`
- **Skill:** `frontend-design`, `clean-code`
- **Priority:** P2 (Medium)
- **Dependencies:** Tasks 2A.*, 2B.*, 2C.*
- **Estimated Time:** 30 minutes

**INPUT:**

- All integrated security services
- Existing dashboard design patterns

**OUTPUT:**

- New `security_dashboard_page.dart`
- Accessible from Settings → Security
- Real-time security metrics display

**VERIFY:**

```bash
# Navigate to Settings → Security
# Expected: Dashboard loads with:
# - Security score gauge (current: 85/100)
# - RLS status (green checkmark)
# - Rate limiter stats
# - Recent security events
```

---

#### Task 3B.2: Create Security Score Gauge Widget

- **Agent:** `mobile-developer`
- **Skill:** `frontend-design`, `clean-code`
- **Priority:** P2 (Medium)
- **Dependencies:** Task 3B.1
- **Estimated Time:** 15 minutes

**INPUT:**

- Security metrics from all services

**OUTPUT:**

- Circular gauge showing 0-100 score
- Color-coded (red <60, yellow 60-80, green >80)
- Breakdown of score components

**VERIFY:**

```bash
# View security dashboard
# Expected: Gauge shows 85/100 in green
# Tap gauge → Shows breakdown:
# - RLS: 100%
# - Input Validation: 100%
# - Rate Limiting: 100%
# - CSP: 100% (web only)
```

---

#### Task 3B.3: Create Rate Limit Monitor Widget

- **Agent:** `mobile-developer`
- **Skill:** `frontend-design`, `clean-code`
- **Priority:** P2 (Medium)
- **Dependencies:** Task 3B.1
- **Estimated Time:** 15 minutes

**INPUT:**

- `RateLimiters` stats from rate_limiter.dart

**OUTPUT:**

- Real-time rate limit usage display
- Shows remaining attempts for each limiter
- Visual progress bars

**VERIFY:**

```bash
# View security dashboard
# Expected: Rate limit section shows:
# - Login: 5/5 attempts remaining
# - File Upload: 10/10 remaining
# - AI Queries: 20/20 remaining

# Make 3 failed login attempts
# Refresh dashboard
# Expected: Login: 2/5 attempts remaining
```

---

#### Task 3B.4: Create RLS Status Card Widget

- **Agent:** `mobile-developer`
- **Skill:** `frontend-design`, `clean-code`
- **Priority:** P2 (Medium)
- **Dependencies:** Task 3B.1
- **Estimated Time:** 10 minutes

**INPUT:**

- `RlsVerificationService` status

**OUTPUT:**

- Card showing RLS verification status
- Last verification timestamp
- Status for each protected table

**VERIFY:**

```bash
# View security dashboard
# Expected: RLS card shows:
# - Overall Status: ✅ Verified
# - Last Check: [timestamp]
# - Tables: lab_results ✅, profiles ✅, prescriptions ✅
```

---

#### Task 3B.5: Create Recent Security Events Widget

- **Agent:** `mobile-developer`
- **Skill:** `frontend-design`, `clean-code`
- **Priority:** P2 (Medium)
- **Dependencies:** Task 3B.1
- **Estimated Time:** 20 minutes

**INPUT:**

- Security logs from all services
- Audit service logs

**OUTPUT:**

- Scrollable list of recent security events
- Color-coded by severity (info, warning, critical)
- Timestamps and event descriptions

**VERIFY:**

```bash
# View security dashboard
# Expected: Events list shows:
# - "✅ Successful login" (green)
# - "⚠️ Rate limit warning: 2 attempts remaining" (yellow)
# - "🔐 RLS verification passed" (green)
```

---

### PHASE X: Verification & Testing (Priority: P0)

#### Task X.1: Create Security Integration Tests

- **Agent:** `test-engineer`
- **Skill:** `testing-patterns`, `tdd-workflow`
- **Priority:** P0 (Critical)
- **Dependencies:** All Phase 2 tasks
- **Estimated Time:** 30 minutes

**INPUT:**

- All integrated security services
- Test patterns from existing tests

**OUTPUT:**

- `test/security/input_validation_test.dart`
- `test/security/rate_limiter_test.dart`
- `test/security/security_integration_test.dart`

**VERIFY:**

```bash
flutter test test/security/
# Expected: All tests pass
```

---

#### Task X.2: Run Security Audit Script

- **Agent:** `security-auditor`
- **Skill:** `vulnerability-scanner`
- **Priority:** P0 (Critical)
- **Dependencies:** All tasks complete
- **Estimated Time:** 10 minutes

**INPUT:**

- Completed integration
- Security audit script

**OUTPUT:**

- Security score: 85/100 or higher
- No critical vulnerabilities
- Audit report

**VERIFY:**

```bash
python .agent/skills/vulnerability-scanner/scripts/security_scan.py .
# Expected: 
# - Security Score: 85/100 ✅
# - Critical Issues: 0
# - High Issues: 0
```

---

#### Task X.3: Manual Security Testing

- **Agent:** `security-auditor`
- **Skill:** `red-team-tactics`
- **Priority:** P0 (Critical)
- **Dependencies:** Task X.2
- **Estimated Time:** 20 minutes

**INPUT:**

- Running application
- Security test scenarios

**OUTPUT:**

- Manual test results
- Penetration test report

**VERIFY:**

```bash
# Test 1: SQL Injection
# Input: '; DROP TABLE users; -- in lab name field
# Expected: Blocked with error message

# Test 2: XSS Attack
# Input: <script>alert('XSS')</script> in name field
# Expected: Sanitized to plain text

# Test 3: Brute Force Login
# Input: 10 failed login attempts
# Expected: Locked out after 5 attempts

# Test 4: Rate Limit Bypass
# Input: 25 rapid AI queries
# Expected: Blocked after 20 queries

# Test 5: RLS Bypass Attempt
# Input: Try to access another user's lab results via API
# Expected: Blocked by RLS policy
```

---

#### Task X.4: Update Documentation

- **Agent:** `documentation-writer`
- **Skill:** `documentation-templates`
- **Priority:** P1 (High)
- **Dependencies:** All tasks complete
- **Estimated Time:** 15 minutes

**INPUT:**

- Integration results
- Security metrics

**OUTPUT:**

- Updated `README.md` with new security score
- Updated `docs/SECURITY_INTEGRATION_GUIDE.md` with completion status
- New `docs/SECURITY_INTEGRATION_PROGRESS.md`

**VERIFY:**

```bash
# Check README.md
# Expected: Security Score updated to 85/100

# Check SECURITY_INTEGRATION_GUIDE.md
# Expected: Status changed to "✅ INTEGRATED"
```

---

## 🔄 Task Dependencies Graph

```
START
  │
  ├─→ 2A.0 (Validation Tests) ──→ 2A.1 (Login Validation) ──→ 2A.2 (DB Validation)
  │                                                                 │
  ├─→ 2B.0 (Rate Limit Tests) ──────────────────────────────────────┤
  │                                                                 │
  │                                                                 ├─→ 2B.1 (Login Rate Limit)
  │                                                                 │
  │                                                                 ├─→ 2B.2 (Upload Rate Limit)
  │                                                                 │
  │                                                                 └─→ 2B.3 (AI Rate Limit)
  │
  ├─→ 2C.1 (RLS Verification) ──→ 2C.2 (Error Recovery)
  │
  ├─→ 3A.1 (CSP Headers)
  │
  └─→ ALL SECURITY LAYERS ACTIVE ──→ PHASE 3 (Integration Tests) ──→ PHASE 4 (Dashboard) ──→ PHASE X (Audit)
```

---

## 🎯 Agent Assignments

| Phase | Tasks | Agent | Skills | Parallel? |
| :--- | :--- | :--- | :--- | :--- |
| **2A** | Validation (TDD) | `mobile-developer` + `test-engineer` | `clean-code`, `tdd-workflow` | ✅ Parallel with 2B.0 |
| **2B** | Rate Limiting (TDD) | `mobile-developer` + `test-engineer` | `clean-code`, `tdd-workflow` | ✅ Parallel with 2A.0 |
| **2C** | RLS + Recovery | `mobile-developer` | `clean-code`, `vulnerability-scanner` | ❌ Single task |
| **3A** | CSP Headers | `mobile-developer` | `vulnerability-scanner` | ❌ Single task |
| **3** | Integration Tests | `test-engineer` | `testing-patterns` | ❌ Sequential |
| **4** | Security Dashboard | `mobile-developer` | `frontend-design` | ✅ Widgets parallel |
| **X** | Final Audit | `security-auditor` | `vulnerability-scanner` | ❌ Sequential |

---

## ⚠️ Risk Assessment

| Risk | Probability | Impact | Mitigation |
| :--- | :--- | :--- | :--- |
| **Rate limiter false positives** | Medium | Medium | Add admin bypass + adjustable limits |
| **CSP breaks existing functionality** | Low | High | Test thoroughly on web platform first |
| **Performance impact from validation** | Low | Low | Validation is lightweight, minimal overhead |
| **RLS verification fails in production** | Low | Critical | Graceful degradation + alert to admin |
| **Dashboard adds app bloat** | Low | Low | Lazy load dashboard, optional feature |

---

## 📊 Estimated Timeline

| Phase | Tasks | Estimated Time | Cumulative |
| :--- | :--- | :--- | :--- |
| **2A** | Input Validation (3 tasks) | 45 minutes | 45 min |
| **2B** | Rate Limiting (3 tasks) | 50 minutes | 1h 35min |
| **2C** | RLS Integration (1 task) | 10 minutes | 1h 45min |
| **3A** | CSP Headers (1 task) | 10 minutes | 1h 55min |
| **3B** | Security Dashboard (5 tasks) | 90 minutes | 3h 25min |
| **X** | Verification (4 tasks) | 75 minutes | 4h 40min |

**Total Estimated Time:** 4 hours 40 minutes

**Recommended Approach:**

- Day 1 (2 hours): Complete Phase 2A, 2B, 2C
- Day 2 (2 hours): Complete Phase 3A, 3B
- Day 3 (1 hour): Complete Phase X verification

---

## ✅ Definition of Done

### Phase 2 Complete When

- [ ] All user inputs are validated before processing
- [ ] Login, uploads, and AI queries are rate limited
- [ ] RLS verification runs on authentication
- [ ] All Phase 2 tests pass
- [ ] No console errors in development

### Phase 3 Complete When

- [ ] CSP headers active on web platform
- [ ] Security dashboard accessible from Settings
- [ ] All dashboard widgets display real-time data
- [ ] Dashboard follows glassmorphic design system
- [ ] All Phase 3 tests pass

### Project Complete When

- [ ] Security score ≥ 85/100
- [ ] All integration tests pass
- [ ] Manual security testing passes
- [ ] Documentation updated
- [ ] No critical or high severity vulnerabilities
- [ ] App runs without errors on all platforms

---

## 🔐 Security Score Breakdown

| Component | Weight | Current | Target | Implementation |
| :--- | :--- | :--- | :--- | :--- |
| **RLS Verification** | 20% | ✅ 20/20 | 20/20 | Already active |
| **Input Validation** | 25% | ❌ 0/25 | 25/25 | Phase 2A |
| **Rate Limiting** | 25% | ❌ 0/25 | 25/25 | Phase 2B |
| **Authentication** | 15% | ✅ 15/15 | 15/15 | Already active |
| **CSP Headers** | 10% | ❌ 0/10 | 10/10 | Phase 3A |
| **Monitoring** | 5% | ❌ 0/5 | 5/5 | Phase 3B |
| **TOTAL** | 100% | **35/100** | **100/100** | All phases |

**Current Score:** 65/100 (RLS + Auth + Encrypted Storage)  
**Target Score:** 85/100 (All above components)

---

## 📝 Notes

### Implementation Order Rationale

1. **Input Validation First** - Foundation for all security
2. **Rate Limiting Second** - Protects against brute force
3. **RLS Verification Third** - Ensures data isolation
4. **CSP Fourth** - Web-specific protection
5. **Dashboard Last** - Monitoring after protections active

### Platform-Specific Considerations

- **Web:** CSP headers only apply to web platform
- **Mobile:** Biometric auth already active (iOS/Android)
- **All Platforms:** Input validation, rate limiting, RLS apply universally

### Rollback Strategy

All changes are additive and can be disabled by:

1. Commenting out validation calls
2. Setting rate limits to `maxAttempts: 999999`
3. Removing CSP meta tag
4. Hiding dashboard from navigation

---

**Plan Status:** ✅ READY FOR IMPLEMENTATION  
**Next Step:** User approval → Begin Phase 2A implementation  
**Estimated Completion:** 3 days (2 hours/day)

