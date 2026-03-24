# Clear Health Architecture

This document describes the technical architecture and choices made for the Clear Health application.

## 🏗 System Overview

Clear Health follows a modern, layered Flutter architecture designed for scalability, maintainability, and security.

```mermaid
graph TD
    A[Flutter Frontend] --> B[Riverpod Providers]
    B --> C[Repositories]
    C --> D[Services]
    D --> E[(Supabase Remote)]
    D --> F[(Hive Local)]
    D --> G[Gemini AI]
    D --> H[Local Hardware: Biometrics/PDF]
```

## 📱 Frontend (Flutter)

- **State Management**: `flutter_riverpod` is used for global state management. It provides a robust, testable, and compile-safe way to manage application logic.
- **Navigation**: Declarative routing for seamless transitions between features.
- **Theming**: A unified `ClearHealthTheme` that supports high-contrast, premium aesthetics with ambient background effects.
- **Icons & Fonts**: Google Fonts (Inter/Roboto) and FontAwesome for a professional UI.

## 💾 Data Layer

### Persistence

- **Remote (Supabase)**: Primary data store using PostgreSQL with `pgvector` for AI-powered semantic search capabilities. Supabase also handles:
  - **Authentication**: Secure JWT-based auth.
  - **Storage**: PDF lab report storage.
  - **Real-time**: Syncing data across devices.
  - **Edge Functions**: Backend ingestion queue (`ingestion_jobs`) with retry/dead-letter controls for resilient AI processing.
- **Local (Hive)**: High-performance NoSQL storage for offline caching, ensuring the app remains functional without an internet connection.

### Security

- **Row Level Security (RLS)**: Enforced in Supabase to ensure users can only access their own data.
- **Biometrics**: `local_auth` integration for an extra layer of local security.
- **Secure Storage**: `flutter_secure_storage` for sensitive credentials.

## 🧠 AI Integration

Clear Health uses a specialized AI pipeline:

- **LlamaParse (PDF preprocessing)**: Converts uploaded lab PDFs into structured markdown, preserving table rows and flags before extraction.
- **Google Gemini (reasoning model)**: Extracts structured lab metrics and generates patient-facing insights/chat responses.
- **Nemotron Embeddings (NVIDIA)**: Creates 2048-dim chunk-level vectors for retrieval (`passage` for ingestion, `query` for search).
- **Nemotron Reranker (NVIDIA)**: Re-ranks pgvector candidates before RAG prompt assembly for higher precision context.

## 🛠 Core Services

- **PDF Service**: Handles generation and rendering of health reports using `pdf` and `printing`.
- **Notification Service**: Manages local scheduled notifications for medications and reminders.
- **Storage Service**: Wrapper around Supabase Storage for secure file handling.
- **Biometric Service**: Abstracts biometric verification logic.
- **Vector Service**: Interfaces with the AI vector database for similarity searches.

## 📁 Directory Structure

The project follows a **Feature-First** structure:

```text
lib/
├── core/                # Shared services, models, and global providers
│   ├── services/        # Concrete implementation of business logic
│   ├── providers/       # Global state providers
│   └── utils/           # Helper functions and extensions
├── features/            # Feature-specific modules
│   ├── lab_results/     # Lab report management
│   ├── trends/          # Data visualization
│   ├── chat/            # AI interaction
│   └── security/        # Security monitoring UI
└── main.dart            # Entry point and global configuration
```

