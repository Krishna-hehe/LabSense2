# Development Guide

This guide will help you set up Clear Health for local development.

## 🛠 Prerequisites

- **Flutter SDK**: Version `^3.10.4`
- **Dart SDK**: Matches Flutter version
- **IDE**: VS Code (recommended) or Android Studio with Flutter/Dart plugins
- **Supabase Account**: For backend services
- **Google AI Studio API Key**: For Gemini AI services

## 🚀 Getting Started

### 1. Clone the Project

```bash
git clone https://github.com/your-username/clear_health.git
cd clear_health
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Environment Variables

The project uses `.env` files for configuration. Create a `.env` file in the root directory:

```env
GEMINI_API_KEY=your_key_here
GEMINI_BASE_URL=https://generativelanguage.googleapis.com/v1beta
GEMINI_CHAT_MODEL=gemini-2.0-flash-lite
SUPABASE_URL=your_supabase_project_url
SUPABASE_ANON_KEY=your_anon_public_key
AI_PROXY_URL=https://your-project.supabase.co/functions/v1/gemini-chat-proxy
SENTRY_DSN=optional_sentry_dsn
```

### 4. Code Generation

If you add new Hive models or other code-generated files, run:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## 🏃‍♂️ Running the App

### Debug Mode (Preferred)

You can run the app using the standard flutter run command. Ensure your `.env` is populated as the app reads from it via `flutter_dotenv`.

```bash
flutter run
```

### Passing defines (Alternative)

If you prefer using `--dart-define`:

```bash
flutter run \
  --dart-define=GEMINI_API_KEY=your_key \
  --dart-define=SUPABASE_URL=your_url \
  --dart-define=SUPABASE_ANON_KEY=your_key
```

## 🧪 Testing

### Unit & Widget Tests

```bash
flutter test
```

### Integration Tests

```bash
flutter test integration_test/app_test.dart
```

## 🏗 Building for Production

### Android

```bash
flutter build apk --release
```

### iOS

```bash
flutter build ios --release
```

## 🤝 Coding Standards

- **Formatting**: Always run `dart format .` before committing.
- **Linting**: Follow the rules defined in `analysis_options.yaml`.
- **Documentation**: Adding JSDoc-style comments for complex logic in `lib/core/services/` is encouraged.

