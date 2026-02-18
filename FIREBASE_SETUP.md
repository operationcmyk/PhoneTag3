# Firebase Setup Instructions

## 1. Create Firebase Project

1. Go to https://console.firebase.google.com
2. Click "Add project"
3. Name it "Phone Tag"
4. Disable Google Analytics (optional)
5. Create project

## 2. Add iOS App

1. Click iOS icon
2. Bundle ID: com.operationcmyk.phonetag
3. App nickname: Phone Tag
4. Download GoogleService-Info.plist
5. Add it to Xcode project root (next to Info.plist)

## 3. Enable Authentication

1. Go to Authentication → Sign-in method
2. Enable "Phone" authentication
3. Configure reCAPTCHA (follow Firebase instructions)

## 4. Set Up Realtime Database

1. Go to Realtime Database → Create Database
2. Start in test mode (we'll add  security rules later)
3. Choose your region (us-central1 recommended)

## 5. Enable Cloud Messaging

1. Go to Cloud Messaging
2. Upload APNs certificate or key (from Apple Developer)
3. Enable push notifications

## Next Steps

After completing this setup:
- Replace the placeholder GoogleService-Info.plist
- Run the app to verify Firebase connection
- Move on to Phase 2: Authentication implementation
