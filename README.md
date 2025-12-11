# PicSecure

**PicSecure** is a secure photo gallery application built with Flutter, designed to protect your private memories with advanced encryption and intelligent face recognition features.

## 🚀 Features

- **Secure Storage**: Encrypts your photos and videos using industry-standard algorithms, ensuring your private media stays private.
- **Smart Face Recognition**: Automatically detects and groups faces using on-device ML (Google ML Kit & TFLite), allowing for easy organization and retrieval.
- **Local Gallery Management**: Seamlessly browse and manage your device's photo gallery with a smooth, responsive UI.
- **Cloud Backup**: (Optional) Securely backup your media to Firebase Cloud Storage.
- **Contact Integration**: Link recognized faces to your contacts for a personalized experience.
- **Cross-Platform**: Runs smoothly on both iOS and Android.

## 🛠 Tech Stack

- **Framework**: [Flutter](https://flutter.dev/)
- **State Management**: [GetX](https://pub.dev/packages/get)
- **Backend / Cloud**: [Firebase](https://firebase.google.com/) (Auth, Firestore, Storage)
- **Local Database**: [Hive](https://pub.dev/packages/hive) & [Flutter Secure Storage](https://pub.dev/packages/flutter_secure_storage)
- **AI / ML**: 
    - [Google ML Kit Face Detection](https://pub.dev/packages/google_mlkit_face_detection)
    - [TFLite Flutter](https://pub.dev/packages/tflite_flutter)
- **Media**: 
    - [Photo Manager](https://pub.dev/packages/photo_manager)
    - [Image Picker](https://pub.dev/packages/image_picker)
    - [Gal](https://pub.dev/packages/gal)

## 📦 Getting Started

### Prerequisites

        Flutter 3.35.1 • channel stable • https://github.com/flutter/flutter.git
        Framework • revision 20f8274939 (4 months ago) • 2025-08-14 10:53:09 -0700
        Engine • hash 6cd51c08a88e7bbe848a762c20ad3ecb8b063c0e (revision 1e9a811bf8) (3 months ago) • 2025-08-13 23:35:25.000Z
        Tools • Dart 3.9.0 • DevTools 2.48.0

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/your-username/picsecure.git
    cd picsecure
    ```

2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

3.  **Run the app:**
    ```bash
    flutter run
    ```

## 🔐 Security

PicSecure uses `encrypt` and `pointycastle` packages for robust encryption. Sensitive data is stored securely using `flutter_secure_storage`.
