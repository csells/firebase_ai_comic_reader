# Firebase AI Comic Reader

A modern Flutter application for reading and analyzing comic books using Gemini
AI. This app transforms traditional comic archives (.cbz, .cbr) into an
interactive, AI-enhanced reading experience.

Need a sample comic to test with? Any cbr or cbz file will work. You can also
check out the comics from the `comics-for-testing` directory in this repository.

![screen recording](readme/screen-recording.gif)

## AI Features

### 1. Import & Analysis
- **Format Support**: Select `.CBZ` (Zip) and `.CBR` (Rar) files.
- **Content Processing**: The app automatically decompresses, initiates a
  multi-stage AI analysis and stores the results in Firebase.

### 2. Panel Mode Guided Reading
- **AI-Driven Reading Order**: Panels are returned by Gemini in their natural
  reading order (typically top-to-bottom, left-to-right), ensuring a seamless
  narrative flow.

### 3. Multi-Lingual AI Summaries
- **Content Summaries**: Gemini analyzes every page and panel to provide
  narrative context in three languages: English (EN), Spanish (ES), and French
  (FR).

## Setup Instructions

### 1. Firebase Project Configuration
1.  **Create Project**: Start a new project in the [Firebase
    Console](https://console.firebase.google.com/).
3.  **Authentication**: Enable **Email/Password** sign-in in the Authentication
    section.
4.  **Cloud Firestore**: Create a database and set the following Security Rules:
    ```javascript
    rules_version = '2';
    service cloud.firestore {
      match /databases/{database}/documents {
        match /users/{userId}/{documents=**} {
          allow read, write: if request.auth != null && request.auth.uid == userId;
        }
      }
    }
    ```
5.  **Firebase Storage**: Create a bucket and set the following Security Rules:
    ```javascript
    rules_version = '2';
    service firebase.storage {
      match /b/{bucket}/o {
        match /comic_store/{userId}/{allPaths=**} {
          allow read, write: if request.auth != null && request.auth.uid == userId;
        }
      }
    }
    ```

### 2. Gemini AI Integration
1.  **Firebase AI Logic**: Navigate to the [Firebase AI
    Logic](https://console.firebase.google.com/project/_/ailogic) section in the
    console.
2.  **Link API Key**: Connect a **Gemini Developer API Key**. The app uses
    `gemini-3-flash-preview` for high-speed vision capabilities.

### 3. Local Development Setup
1.  **Firebase CLI**: Ensure you have the [Firebase
    CLI](https://firebase.google.com/docs/cli) installed.
2.  **FlutterFire CLI**:
    ```bash
    dart pub global activate flutterfire_cli
    ```
3.  **Configure Project**:
    ```bash
    flutterfire configure
    ```
4.  **Web CORS (Important)**: To allow cross-origin image processing for Panel
    Mode on the web:
    - Create `cors.json`:
      ```json
      [{"origin": ["*"], "method": ["GET"], "maxAgeSeconds": 3600}]
      ```
    - Apply it:
      ```bash
      gsutil cors set cors.json gs://YOUR_BUCKET_NAME.firebasestorage.app
      ```

## AI Implementation Insights

### Single-Pass AI Analysis
The core logic resides in `GeminiService`, which leverages the
`FirebaseAI.googleAI()` SDK to send comic pages to Gemini in a single-pass
analysis. This efficiency allows us to extract:
1.  **OCR Text**: Narrative extraction of all speech bubbles and text.
2.  **Page Summaries**: High-level context for the entire page in 3 languages.
3.  **Panel Detection**: Normalized bounding box coordinates `[ymin, xmin, ymax,
    xmax]` on a 0-1000 scale.
4.  **Panel Reading Order**: The prompt explicitly instructs the LLM to return
    panels in their natural reading order, eliminating the need for complex
    app-side sorting algorithms.
5.  **Panel-Specific Summaries**: Unique narrative descriptions for every
    detected panel in 3 languages.
