# Firebase AI Comic Reader

A modern Flutter application for reading and analyzing comic books using Gemini AI.

## Core Use Cases

### 1. User Authentication
*   **Log In / Sign Up**: Users can log in using their credentials. If an account doesn't exist, it is automatically created on Firebase.
*   **Terminology**: The app uses "Email" and "Password" for a familiar login experience.

### 2. Comic Library Management
*   **Add Comic**: Press the floating action button (+) to navigate your hard drive and select a comic file.
*   **Supported Formats**: `.CBZ` (Zip) and `.CBR` (Rar) archives are supported.
*   **Automated Import**: Upon selection, the app:
    *   Decompresses the archive.
    *   Uploads pages to Firebase Storage.
    *   Generates a thumbnail for the library view.
    *   Initiates AI analysis for all pages.

### 3. AI-Powered Analysis
*   **Model**: Powered by the latest **Gemini 3 Flash Preview** for high-speed, intelligent OCR and visual analysis.
*   **Panel Detection**: Automatically identifies the bounding box coordinates [0-1000] for every comic panel.
*   **Multi-Language Summaries**: For every page and every detected panel, the AI generates narrative summaries in:
    *   English (EN)
    *   Spanish (ES)
    *   French (FR)
*   **Text Extraction**: Extracts and arranges comic text into a narrative flow.

### 4. Advanced Reading Experience
*   **Page Mode**: Default navigation using a slider or arrow keys/keyboard.
*   **Smart Mode (Panel-by-Panel)**: Toggle the "Science" icon to switch to Smart Mode. The reader will zoom in and navigate panel-by-panel, providing a focused, guided reading experience.
*   **On-Demand Language Switching**: Swap between English, Spanish, and French for both page and panel summaries instantly.
*   **Summary Toggle**: Show or hide the AI-generated summaries as desired.

## Setup Instructions

To get this project running, you need to set up a Firebase project and configure your local environment.

### 1. Firebase Project Setup
1.  Go to the [Firebase Console](https://console.firebase.google.com/) and create a new project.
2.  **Enable Billing**: Ensure your project is on the **Blaze (Pay-as-you-go) plan** to use the Vertex AI / Gemini features.
3.  **Authentication**: 
    - Enable the **Email/Password** sign-in provider.
4.  **Cloud Firestore**:
    - Create a database in **Production Mode** (or Test Mode for immediate start).
    - Set the following Security Rules:
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
5.  **Firebase Storage**:
    - Create a storage bucket.
    - Set the following Security Rules to allow user-specific access and directory listing:
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
6.  **Gemini API (Vertex AI)**:
    - Go to the [Firebase AI Logic settings](https://console.firebase.google.com/project/_/ailogic/settings).
    - Link a **Gemini Developer API key** (this is required for the `firebase_ai` package to communicate with Google's models).

### 2. Local Configuration
1.  Install the [Firebase CLI](https://firebase.google.com/docs/cli) if you haven't already.
2.  Install the [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup):
    ```bash
    dart pub global activate flutterfire_cli
    ```
3.  Run the configuration command in your project root to link the app to your Firebase project:
    ```bash
    flutterfire configure
    ```
    This will generate the necessary `firebase_options.dart` file.

### 3. Web CORS Setup (Crucial for Smart Mode)
For the Smart Mode (panel zooming) to work on the web, your browser must be allowed to process images from your Storage bucket.
1.  Create a file named `cors.json` in your project root with the following content:
    ```json
    [
      {
        "origin": ["*"],
        "method": ["GET"],
        "maxAgeSeconds": 3600
      }
    ]
    ```
2.  Apply the CORS policy using `gsutil`:
    ```bash
    gsutil cors set cors.json gs://YOUR_BUCKET_NAME.firebasestorage.app
    ```
    *Replace `YOUR_BUCKET_NAME` with your actual bucket ID from the Firebase console.*

## Implementation Details

*   **Flutter**: The primary framework for the cross-platform application.
*   **Firebase Auth**: Handles secure user authentication and account lifecycle.
*   **Firebase Storage**: Stores comic page images and thumbnails.
*   **Cloud Firestore**: Manages comic metadata, AI predictions, and multilingual summaries.
*   **Firebase AI (Gemini)**: Orchestrates the single-pass analysis for OCR, translation, and object detection (panels).
*   **PageController**: Manages smooth transitions between comic pages.
*   **PanelView**: A custom widget for cropping and displaying individual panels in Smart Mode.
