# SwiftWing - App Store Privacy Nutrition Labels

**Prepared for:** App Store Connect Privacy Section
**Last Updated:** January 25, 2026

This document provides the exact responses needed for Apple's App Privacy questions in App Store Connect.

---

## Privacy Practices Overview

**Does your app collect data?**
**Answer:** YES (but with important context - see below)

---

## Section 1: Data Used to Track You

**Does your app or third-party partners collect data in order to track users across apps and websites owned by other companies?**

**Answer:** NO

**Explanation:** SwiftWing does not track users. We do not use:
- Advertising SDKs
- Analytics frameworks (Mixpanel, Amplitude, etc.)
- Social media SDKs (Facebook, Google Sign-In, etc.)
- Cross-app tracking identifiers

---

## Section 2: Data Linked to You

**Does your app collect data that is linked to the user's identity?**

**Answer:** NO

**Explanation:** SwiftWing does not create user accounts. All data is stored locally on the device and is not linked to any user identity, email, or account.

---

## Section 3: Data Not Linked to You

**Does your app collect data that is NOT linked to the user's identity?**

**Answer:** YES

### Data Types Collected (Not Linked to You)

#### 1. Photos and Videos
- **Data Type:** Photos and Videos
- **Usage Purpose:** App Functionality
- **Details:** Camera photos of book spines are temporarily captured and sent to our AI backend for book identification. Photos are immediately deleted after processing and are never stored.

#### 2. User Content
- **Data Type:** Other User Content
- **Usage Purpose:** App Functionality
- **Details:** Book library metadata (title, author, ISBN, cover URL) is stored locally on the user's device using SwiftData. This data never leaves the device except during the initial scan for AI processing.

---

## Detailed Data Collection Breakdown

### Category: Photos and Videos

**Question:** Does your app collect photos or videos?
**Answer:** YES

**Question:** What do you use photos or videos for?**
- [x] App Functionality
- [ ] Analytics
- [ ] Product Personalization
- [ ] Advertising or Marketing
- [ ] Other Purposes

**Question:** Are photos or videos linked to the user?**
**Answer:** NO

**Question:** Do you or your third-party partners use photos or videos for tracking?**
**Answer:** NO

---

### Category: Other User Content

**Question:** Does your app collect other user content?
**Answer:** YES

**Question:** What type of other user content?**
- Book library metadata (title, author, ISBN, cover URLs, format, confidence scores)

**Question:** What do you use other user content for?**
- [x] App Functionality
- [ ] Analytics
- [ ] Product Personalization
- [ ] Advertising or Marketing
- [ ] Other Purposes

**Question:** Is other user content linked to the user?**
**Answer:** NO (stored locally, no user accounts)

**Question:** Do you or your third-party partners use other user content for tracking?**
**Answer:** NO

---

## Additional Privacy Details

### Data Retention and Deletion

**Question:** How long do you retain this data?**
- **Camera photos:** Deleted immediately after AI processing (seconds)
- **Book metadata:** Stored indefinitely on user's device until manually deleted
- **Server-side retention:** Zero - no data retained on our servers

**Question:** How can users request deletion of their data?**
- Delete individual books from the in-app library
- Delete entire library by uninstalling the app
- No server-side data to delete (all local)

---

## Third-Party SDKs and Partners

**Question:** Do you share data with third-party partners?**
**Answer:** NO

**Explanation:** SwiftWing uses our first-party Talaria API (`https://api.oooefam.net`) for AI processing. Talaria is operated by the same developer (OOOEfam.net) and is not a third-party service. No data is shared with external companies.

---

## Privacy Policy URL

**Question:** Where is your privacy policy?**
**Answer:** https://github.com/jukasdrj/swiftwing/blob/main/PRIVACY.md

**Alternative URLs (if GitHub not preferred):**
- Host PRIVACY.md on oooefam.net/swiftwing/privacy
- Include in App Store description with "See Privacy Policy in app description"

---

## App Privacy Details String (for Submission)

**Privacy Policy Summary (for App Store Connect):**

> SwiftWing collects camera photos of book spines to provide AI-powered book identification. Photos are sent to our Talaria API for processing and are immediately deleted after analysis. Book metadata (title, author, ISBN) is stored locally on your device and never leaves your device except during the initial scan. We do not track users, create accounts, or share data with third parties. Your library is yours alone.

---

## Privacy Nutrition Label Preview

Based on the above answers, SwiftWing's App Store privacy label will show:

### Data Used to Track You
**NONE**

### Data Linked to You
**NONE**

### Data Not Linked to You
- **Photos** - Used for App Functionality
- **Other User Content** - Used for App Functionality

---

## Compliance Checklist

- [x] Privacy policy published and accessible
- [x] Terms of service published
- [x] App Store privacy questions answered accurately
- [x] Privacy nutrition label reflects actual data practices
- [x] No tracking or analytics SDKs
- [x] No user accounts or linked data
- [x] Camera usage description in Info.plist (NSCameraUsageDescription)
- [x] Local-first data storage (SwiftData)
- [x] HTTPS encryption for network requests

---

## Notes for App Store Submission

1. **Privacy Policy Link:** Upload PRIVACY.md to GitHub and use the raw URL, or host on oooefam.net
2. **Camera Permission:** NSCameraUsageDescription already in Info.plist: "SwiftWing uses your camera to scan book spines for automatic identification."
3. **Simplicity is a Feature:** Emphasize in App Store description that SwiftWing has no tracking, no accounts, no cloud sync
4. **Privacy as Selling Point:** "Your library is yours alone - all data stored locally"

---

**Privacy Label Status:** ✅ READY FOR SUBMISSION

**Key Differentiator:** SwiftWing's privacy-first approach (local-only storage, no tracking) is a competitive advantage over other book scanning apps.
