# Clear Health (LabSense) Workflow & Data Flow Diagrams

This document illustrates the core workflows and data architecture of the application, encompassing Authentication, Document Processing, Trend Analysis, and AI-powered interactions.

## 1. High-Level System Workflow

This flowchart demonstrates how users navigate the system and how modules interact with our remote services (Supabase & Gemini AI).

```mermaid
graph TD
    User([User])
    
    subgraph Auth Flow
        User -->|Log in / Sign up| Auth[Supabase Auth]
        Auth -->|Biometric Check| BioAuth[Local Biometrics via local_auth]
    end

    BioAuth --> AppHome[App Dashboard]

    subgraph Document Processing Flow
        AppHome -->|Upload Report| UploadLab[Upload Lab PDF/Image]
        UploadLab -->|Store File| SupabaseStorage[(Supabase Storage)]
        SupabaseStorage -->|Create Ingestion Job| IngestionQueue[(ingestion_jobs queue)]
        IngestionQueue -->|Worker retries/dead-letter| EdgeWorker[Edge Processing Worker]
        UploadLab -->|Parse PDF to Markdown| LlamaParse[LlamaParse]
        LlamaParse -->|Extract Structured Metrics| GeminiExtract[Gemini Data Extraction]
        GeminiExtract -->|Save Structured Metrics| SupabaseDB[(Supabase PostgreSQL)]
        GeminiExtract -->|Chunk + Embed| NemotronEmbed[Nemotron Embed (2048)]
        NemotronEmbed -->|Store Chunk Vectors| PGVector[(pgvector Table)]
        SupabaseDB -.->|Offline Sync| Hive[(Local Hive DB)]
    end

    subgraph AI Chat & RAG Flow
        AppHome -->|Ask Medical Question| ChatUI[AI Health Chat]
        ChatUI -->|Embed Query| VectorSearch[Nemotron Query Embedding]
        VectorSearch -->|Fetch Top-20| PGVector
        PGVector -->|Rerank Candidates| Reranker[Nemotron Reranker]
        Reranker -->|Top Context Chunks| RAGPrompt[RAG Prompt Assembly]
        RAGPrompt -->|Ask LLM| GeminiChat[Gemini AI]
        GeminiChat -->|Contextual Answer| ChatUI
    end

    subgraph Analytics & Trends
        AppHome -->|View Dashboards| DashUI[Trend Charts]
        SupabaseDB -->|Load Historical Data| DashUI
        DashUI -->|Generate Smart Summaries| GeminiInsight[Gemini Insights]
        GeminiInsight -->|Display Actionable Tips| DashUI
    end
```

## 2. Detailed Process State Diagram

This state diagram depicts the step-by-step state transitions of the app for the primary user journeys.

```mermaid
stateDiagram-v2
    [*] --> Authentication
    
    state Authentication {
        [*] --> Login_Signup
        Login_Signup --> Supabase_Auth_Verification
        Supabase_Auth_Verification --> Biometric_Lock
        Biometric_Lock --> [*]
    }
    
    Authentication --> Dashboard
    
    state Dashboard {
        [*] --> Select_Patient_Profile
        Select_Patient_Profile --> View_Historical_Trends
        Select_Patient_Profile --> View_AI_Insights
    }
    
    Dashboard --> Document_Ingestion : Upload New Lab Report
    
    state Document_Ingestion {
        [*] --> Select_File
        Select_File --> Upload_To_Supabase
        Upload_To_Supabase --> Parse_With_LlamaParse
        Parse_With_LlamaParse --> Trigger_AI_Parsing
        note right of Trigger_AI_Parsing
            Gemini interprets
            structured markdown output
            from LlamaParse
        end note
        Trigger_AI_Parsing --> Save_To_Database
        Save_To_Database --> Chunk_Report_Markdown
        Chunk_Report_Markdown --> Generate_Vector_Embeddings
        Generate_Vector_Embeddings --> Store_In_pgvector
        Store_In_pgvector --> [*]
    }
    
    Document_Ingestion --> Dashboard : Refresh UI with New Data
    
    Dashboard --> Health_Assistant_Chat : Initialize Chat
    
    state Health_Assistant_Chat {
        [*] --> Await_User_Query
        Await_User_Query --> Process_Query
        Process_Query --> Similarity_Search
        note right of Similarity_Search
            Matches query against historical
            chunk embeddings in pgvector
        end note
        Similarity_Search --> Rerank_Candidates
        Rerank_Candidates --> Construct_RAG_Prompt
        Construct_RAG_Prompt --> Request_Gemini_Response
        Request_Gemini_Response --> Display_Answer
        Display_Answer --> Await_User_Query
    }
    
    Health_Assistant_Chat --> Dashboard : Exit Chat
```

