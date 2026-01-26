# SwiftWing Privacy Policy

**Last Updated:** January 25, 2026
**Effective Date:** January 25, 2026

SwiftWing ("we", "our", or "the app") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, and safeguard your information when you use our iOS application.

## Information We Collect

### 1. Camera Data
**What we collect:** When you scan a book spine, SwiftWing captures photos using your device's camera.

**How we use it:**
- Photos are temporarily processed and sent to our AI backend (Talaria API at `https://api.oooefam.net`) for book identification
- Photos are **never stored** on our servers or your device after processing
- Images are transmitted over HTTPS (encrypted connection)
- After AI analysis completes, images are immediately deleted from our servers

**Your control:** You can revoke camera access at any time in iOS Settings → SwiftWing → Camera.

### 2. Book Metadata
**What we collect:** After scanning, we store book information locally on your device:
- Book title
- Author name
- ISBN (International Standard Book Number)
- Cover image URL (if available)
- Book format (hardcover, paperback, etc.)
- Scan confidence score

**How we use it:**
- All book data is stored **locally** using SwiftData (Apple's on-device database)
- Book metadata **never leaves your device** except during the initial scan
- No cloud sync, no remote backups
- You have full control to delete any book from your library

### 3. Network Activity
**What we collect:** When scanning books:
- Your device sends JPEG images to our Talaria API via HTTPS
- Our API returns book metadata via Server-Sent Events (SSE) streaming
- If you're offline, scans are queued locally and uploaded when network returns

**What we do NOT collect:**
- We do not track your IP address
- We do not create user profiles
- We do not log scan history on our servers
- We do not share data with third parties

## Data We Do NOT Collect

SwiftWing does **not** collect:
- ❌ User accounts or login credentials
- ❌ Email addresses or contact information
- ❌ Location data or GPS coordinates
- ❌ Device identifiers (IDFA, IDFV)
- ❌ Analytics or usage tracking
- ❌ Crash reports or diagnostics (unless you opt-in via iOS)
- ❌ Browsing history or app usage patterns

## Third-Party Services

### Talaria AI Backend
SwiftWing uses our proprietary Talaria API (`https://api.oooefam.net`) for AI-powered book recognition.

**Data sent to Talaria:**
- JPEG images of book spines (temporary, deleted after processing)
- Device ID (randomly generated, not tied to you personally)

**Data received from Talaria:**
- Book metadata (title, author, ISBN, cover URL)
- Processing progress updates

**Talaria's data practices:**
- Images deleted immediately after processing
- No long-term data retention
- No data sharing with third parties
- Encrypted HTTPS connections only

**Talaria is operated by:** OOOEfam.net (same developer as SwiftWing)

## Children's Privacy

SwiftWing does not knowingly collect personal information from children under 13. The app is designed for general audiences and does not require age verification. If you believe we have inadvertently collected information from a child under 13, please contact us to request deletion.

## Data Retention

- **Camera photos:** Deleted immediately after AI processing (seconds)
- **Book metadata:** Stored locally on your device until you delete it
- **Offline queue:** Cleared automatically after successful upload
- **No server-side retention:** We do not retain any user data on our servers

## Your Rights

You have the right to:
- **Access:** View all books in your local library
- **Delete:** Remove any book from your library at any time
- **Export:** (Future feature) Export your library to CSV/JSON
- **Revoke permissions:** Disable camera access in iOS Settings

## Data Security

SwiftWing implements the following security measures:
- **HTTPS encryption** for all network communications
- **Local-only storage** using Apple's SwiftData framework
- **No cloud sync** means your data never leaves your device (except during scans)
- **Sandboxed iOS environment** protects your library from other apps

## Changes to This Policy

We may update this Privacy Policy from time to time. Changes will be reflected by updating the "Last Updated" date at the top of this document. Continued use of SwiftWing after changes constitutes acceptance of the updated policy.

## Contact Us

If you have questions about this Privacy Policy or SwiftWing's data practices:

- **Email:** privacy@oooefam.net
- **GitHub Issues:** https://github.com/jukasdrj/swiftwing/issues
- **App Developer:** OOOEfam.net

## California Privacy Rights (CCPA)

If you are a California resident, you have the right to:
- Know what personal information we collect
- Request deletion of your personal information
- Opt-out of the sale of personal information (we do not sell data)

**Note:** SwiftWing stores all data locally on your device. To delete your data, simply delete the app or use the in-app delete function.

## GDPR Compliance (European Users)

SwiftWing complies with the General Data Protection Regulation (GDPR):
- **Legal basis for processing:** Legitimate interest (providing book scanning functionality)
- **Data minimization:** We only collect data necessary for app functionality
- **Right to erasure:** Delete any book from your library at any time
- **No automated decision-making:** AI recognition is for metadata only, no profiling

## App Store Privacy Nutrition Labels

SwiftWing's App Store listing includes the following privacy disclosures:

### Data Used to Track You
**None** - SwiftWing does not track you across apps or websites.

### Data Linked to You
**None** - SwiftWing does not create user accounts or link data to your identity.

### Data Not Linked to You
- **Photos** - Used only for book scanning, not stored
- **User Content** - Book library stored locally on your device

---

**Your privacy matters.** SwiftWing is designed with privacy-first principles: local-first storage, no user accounts, no tracking, and minimal data collection. Your library is yours alone.
