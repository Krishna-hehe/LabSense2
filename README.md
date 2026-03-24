# Clear Health

![Build Status](https://img.shields.io/badge/build-passing-brightgreen) ![License](https://img.shields.io/badge/license-MIT-blue) ![Flutter](https://img.shields.io/badge/Flutter-3.10.4-02569B?logo=flutter)

**Clear Health** (formerly LabSense) is an intelligent health monitoring application built with Flutter. It empowers users to upload lab reports, receive AI-powered insights, tracking health trends monitoring, and manage family health profiles securely.

## Features

- **📄 Lab Report Management**: Upload PDF lab reports and extract data automatically.
- **🤖 AI-Powered Insights**: Get personalized health summaries, optimization tips, and predictions.
- **🔒 Secure Authentication**: Biometric login (Fingerprint/Face ID) and Supabase authentication.
- **👨‍👩‍👧‍👦 Multi-Profile Support**: Manage health records for the entire family.
- **📈 Trend Analysis**: Visualize health metrics over time with interactive charts.
- **💊 Medication Tracking**: Keep track of prescriptions and schedules.
- **🔔 Smart Notifications**: Reminders for medication and appointments.
- **📤 Data Export**: Generate comprehensive PDF health reports.

## Tech Stack

- **Frontend**: [Flutter](https://flutter.dev/)
- **Backend**: [Supabase](https://supabase.io/) (Auth, Database, Storage, Edge Functions)
- **AI**: Google Gemini (analysis/chat generation) + NVIDIA embeddings/reranking
- **State Management**: [Riverpod](https://riverpod.dev/)
- **Local Storage**: [Hive](https://docs.hivedb.dev/)
- **Charts**: [fl_chart](https://pub.dev/packages/fl_chart)

## Quick Start

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.
- Detailed setup guide available in [docs/setup.md](./docs/setup.md) (create this if needed).

### Installation

1. **Clone the repository:**

    ```bash
    git clone https://github.com/your-username/clear_health.git
    cd clear_health
    ```

2. **Install dependencies:**

    ```bash
    flutter pub get
    ```

3. **Configure Environment:**
    Create a `.env` file in the root directory:

    ```env
    GEMINI_API_KEY=your_gemini_key
    GEMINI_BASE_URL=https://generativelanguage.googleapis.com/v1beta
    GEMINI_CHAT_MODEL=gemini-2.0-flash-lite
    # REQUIRED for runtime AI calls (all app targets). Keeps Gemini keys server-side:
    AI_PROXY_URL=https://your-project.supabase.co/functions/v1/gemini-chat-proxy
    # REQUIRED for AI proxy requests from web/mobile clients:
    AI_PROXY_ANON_KEY=your_supabase_anon_public_key
    # Optional: public base URL used to construct doctor-view share links
    SHARE_BASE_URL=https://your-app-domain.com
     LLAMAPARSE_API_KEY=your_key
     VECTOR_API_KEY=your_key
     # Optional split keys (if you use separate NVIDIA keys per endpoint):
     VECTOR_EMBED_API_KEY=your_embed_key
     VECTOR_RERANK_API_KEY=your_rerank_key
     # VECTOR_BASE_URL=https://integrate.api.nvidia.com/v1
     SUPABASE_URL=your_url
     SUPABASE_ANON_KEY=your_key
    INGESTION_CRON_SECRET=strong_random_secret
    INGESTION_PROCESSOR_URL=https://your-project.supabase.co/functions/v1/ingestion-processor
    INGESTION_PROCESSOR_TOKEN=strong_random_secret_for_worker_to_processor_calls
     ```
    Web login/auth will fail with 404s if these are missing or invalid.
    `SUPABASE_URL` must be `https://<project-ref>.supabase.co`.
    ⚠️ Never place `SUPABASE_SERVICE_ROLE_KEY` in client `.env` (this file is bundled with the app).
    Set service-role secrets only in Supabase Edge Function secrets.
    ⚠️ For production web, do not rely on direct `GEMINI_API_KEY` usage in client code.
    Use `AI_PROXY_URL` + `gemini-chat-proxy`.

4. **Apply ingestion queue migrations (backend hardening):**

    - `supabase/migrations/006_fix_profiles_family_schema.sql`
    - `supabase/migrations/003_nemotron_2048_chunking.sql`
    - `supabase/migrations/004_ingestion_queue_backend_hardening.sql`
    - `supabase/migrations/005_security_self_test.sql`

    This repo now expects the profile/family schema from
    `006_fix_profiles_family_schema.sql`. Without it, profile settings and
    family profiles run in a reduced compatibility mode.

5. **Deploy Supabase functions:**

    - `ingest-lab-report`
    - `ingestion-status`
    - `create-lab-upload-url`
    - `process-ingestion-jobs`
    - `ingestion-processor`
    - `audit-log`
    - `gemini-chat-proxy` (required for runtime AI calls)

6. **Set production web security headers at hosting layer** (required):

    - `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
    - `X-Frame-Options: DENY`
    - `X-Content-Type-Options: nosniff`
    - `Referrer-Policy: strict-origin-when-cross-origin`
    - `Permissions-Policy: geolocation=(), microphone=(), camera=(), payment=(), usb=(), serial=()`
    - `Cross-Origin-Opener-Policy: same-origin`
    - `Cross-Origin-Resource-Policy: same-origin`
    - `X-XSS-Protection: 0`
    - `Content-Security-Policy: default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; script-src 'self' https://www.gstatic.com 'wasm-unsafe-eval'; worker-src 'self' blob:; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com data:; img-src 'self' data: https:; connect-src 'self' https://*.supabase.co wss://*.supabase.co https://generativelanguage.googleapis.com https://integrate.api.nvidia.com https://www.gstatic.com; form-action 'self'; upgrade-insecure-requests`

7. **Run the app:**

    ```bash
    flutter run
    ```

8. **Run local verification before release:**

    ```bash
    flutter analyze
    flutter test
    dart run scripts/security_verify.dart
    dart run scripts/release_readiness.dart
    ```

## Documentation

- **[Features Guide](./docs/FEATURES.md)**: Detailed breakdown of what Clear Health can do.
- **[Technical Architecture](./docs/ARCHITECTURE.md)**: Overview of the tech stack and system design.
- **[Development Guide](./docs/DEVELOPMENT_GUIDE.md)**: Setup instructions and development workflows.
- **[User Manual](./docs/USER_MANUAL.md)**: Step-by-step documentation for end users.
- **[Contributing Guidelines](CONTRIBUTING.md)**: How to help improve Clear Health.
- **[Changelog](CHANGELOG.md)**: Version history and updates.
- **[License](LICENSE)**: MIT License details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
