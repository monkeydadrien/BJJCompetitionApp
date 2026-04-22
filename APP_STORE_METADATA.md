# App Store Metadata — BJJ Companion

Draft values for App Store Connect submission. Character limits enforced.
Fill this out offline, paste into App Store Connect when enrollment clears.

**App identity**
- Bundle ID: `dev.pinnacleapp.bjjcompanion`
- Seller: Pinnacle AppDev LLC
- Primary locale: English (U.S.)

---

## 1. App Information (review-gated — changing requires a new binary)

### App Name — 30 char max
Proposed: **`BJJ Companion`** (13/30)

Alternates if taken:
- `BJJ Companion – Brackets` (24/30)
- `Jiu Jitsu Companion` (19/30)

> App Store search ranks name > subtitle > keywords. Leave room in the name for a high-value keyword if we discover one during ASO research.

### Subtitle — 30 char max
Proposed: **`Tournaments, brackets, events`** (30/30)

Alternates:
- `Tournament brackets & athletes` (30/30)
- `IBJJF & AGF bracket tracker` (27/30)
- `Find your next jiu jitsu comp` (29/30)

### Category
- **Primary:** Sports
- **Secondary:** Reference

> Sports is obvious. Reference beats Utilities because the app is fundamentally a lookup tool (events, brackets, athletes) rather than a productivity utility.

---

## 2. Store Listing (editable anytime)

### Promotional Text — 170 char max (updatable without review)
Proposed (142/170):

> Every IBJJF and AGF tournament in one place. Track your teammates, filter by distance, and pull live brackets the morning of the event. Free, no ads.

Use this slot to surface seasonal things without re-submitting: "Pans 2026 brackets now live," "WNO coverage added," etc.

### Description — 4000 char max (updatable without review)
Proposed (1,140/4,000 — intentionally tight; long descriptions aren't read):

```
BJJ Companion is the fastest way to find your next tournament and track
the people you care about on the mats.

— EVENTS
Browse every upcoming IBJJF, AGF, and major open tournament in one
place. Filter by distance from your home city (50, 100, 250, 500 mi)
or by date. See venue, registration deadline, and who's competing.

— BRACKETS
Pull live brackets on tournament morning from the organizer's system
without opening a browser or fighting a PDF. Search your name, tap
your division, see your path to the podium.

— TRACKING
Follow teammates and rival athletes. Track whole teams. The app
highlights when anyone you're following registers for an upcoming
event so you never miss a rematch.

— BUILT FOR COMPETITORS
No accounts. No ads. No tracking. No third-party analytics. The app
stores your preferences locally on your device — nothing about you
leaves your phone.

— MADE BY A PRACTITIONER
Built by a blue belt who got tired of squinting at bracket PDFs on
tournament morning. If something looks wrong, email support and it
usually gets fixed by the next day.

Data sources: IBJJF.com, AGFgear.com, and the respective tournament
organizers' public bracket systems.

Privacy policy: https://monkeydadrien.github.io/BJJCompetitionApp/privacy.html
Support: https://monkeydadrien.github.io/BJJCompetitionApp/support.html
```

> Review the belt claim before release — adjust to accurate rank.

### Keywords — 100 char max, comma-separated, no spaces after commas
Proposed (99/100):

```
jiu jitsu,bjj,ibjjf,agf,tournament,bracket,grappling,competition,nogi,gi,martial arts,jujitsu
```

Notes:
- Do NOT repeat words already in the app name/subtitle — Apple indexes those automatically. "Companion," "brackets," "tournaments," "events" are already covered by name/subtitle.
- `jiu jitsu` and `jujitsu` both included — common misspellings/variants matter for search.
- `nogi` and `gi` are short but high-intent for this audience.

### What's New — 4000 char (per version)
Launch version 1.0:

```
First release. Browse tournaments, pull live brackets, track
athletes and teams, filter by distance from your home city.

Found a bug or have a feature request? Email support@pinnacleapp.dev.
```

### Support URL
`https://monkeydadrien.github.io/BJJCompetitionApp/support.html`

### Marketing URL (optional — leave blank for now)
(none)

### Privacy Policy URL
`https://monkeydadrien.github.io/BJJCompetitionApp/privacy.html`

### Copyright
`© 2026 Pinnacle AppDev LLC`

---

## 3. Pricing & Availability
- **Price tier:** Free
- **Availability:** All countries/regions
- **Pre-orders:** No
- **Content rights:** I do own or have licensed all rights to the content in my app
  - *Note:* Public tournament data + publicly available bracket data. Not third-party copyrighted content.

---

## 4. App Privacy (Nutrition Label)

Apple's privacy questionnaire. Based on current implementation:

### Data collection: **Yes**, we collect limited data.

| Data type | Collected? | Linked to user? | Used for tracking? | Purpose |
|---|---|---|---|---|
| **Crash Data** (via Sentry) | Yes | No | No | App Functionality |
| **Performance Data** (via Sentry) | Yes | No | No | App Functionality |
| **Other Diagnostic Data** (breadcrumbs) | Yes | No | No | App Functionality |

Everything else (Contact Info, Health, Financial, Location, Contacts, User Content, Identifiers, Usage Data, Sensitive Info, Browsing History, Search History, Purchases) — **Not collected**.

### Tracking: **No.**
No IDFA collected. No third-party SDKs used for advertising or cross-app tracking.

---

## 5. Age Rating Questionnaire

All answers: **None** / **No** — yields **4+** rating.

Specifically:
- Cartoon/Fantasy Violence: None
- Realistic Violence: None (no BJJ match footage shipping with the app)
- Prolonged Graphic/Sadistic Violence: None
- Profanity or Crude Humor: None
- Mature/Suggestive Themes: None
- Horror/Fear Themes: None
- Medical/Treatment Info: None
- Gambling and Contests: None
- Unrestricted Web Access: No
- User Generated Content: No

Result: **4+**

---

## 6. App Review Information (shown only to Apple reviewers)

- **Sign-in required:** No
- **Demo account:** N/A
- **Contact info:**
  - First name: Adrien
  - Last name: Ibarra
  - Phone: (on file)
  - Email: developer@pinnacleapp.dev
- **Notes to reviewer:**

```
BJJ Companion aggregates publicly available tournament data from
IBJJF and AGF and surfaces publicly available brackets through a
backend proxy (api.pinnacleapp.dev) that we operate. All data
sources are publicly accessible without authentication. The app
has no user accounts, in-app purchases, or advertising.

For testing, tap any tournament in the Events tab to browse its
divisions and brackets. The Tracking tab demonstrates following
athletes and teams. No login required.
```

---

## 7. Version Info
- **Version string:** `1.0`
- **Build number:** `1` (increment every TestFlight upload)

---

## 8. Screenshots — REQUIRED (biggest remaining work)

Apple requires screenshots at these sizes:

| Device class | Resolution | Required? | How many |
|---|---|---|---|
| iPhone 6.9" (16 Pro Max / 17 Pro Max) | 1320 × 2868 | **Yes** | 3–10 |
| iPhone 6.5" (legacy) | 1284 × 2778 | Optional if 6.9" provided | 3–10 |
| iPad 13" (M4) | 2064 × 2752 | Only if iPad support declared | 3–10 |

Recommended shot list (6 screenshots):
1. **Events list** — distance filter set to "100 mi," nearby tournaments visible
2. **Event detail** — registration deadline, date, venue, athletes competing
3. **Brackets** — a live bracket with a tap target highlighted
4. **Tracking — Teams** — a few tracked teams with upcoming comps
5. **Tracking — Athletes** — tracked athletes with next comp
6. **Settings / Home City** — showing the privacy-first framing

Style decisions to make:
- **Plain simulator shots** (fastest, most honest) vs **marketing overlays** with captions ("Find tournaments near you" over a device frame)?
- My vote: start with plain simulator screenshots. They're faster, they pass review, and you can upgrade to stylized ones after launch data tells you what resonates.

Screenshot capture recipe:
1. Xcode → run on iPhone 17 Pro Max simulator
2. Seed the simulator with realistic data (real upcoming events, plausible tracked athletes)
3. `⌘S` in the simulator saves a full-res PNG to the desktop
4. Upload to App Store Connect directly — no resizing needed

---

## 9. App Icon (1024 × 1024 PNG, no transparency, no rounded corners)

You need a 1024×1024 PNG for the store listing separate from the in-app icon bundle.
Current status: **NOT DONE** — placeholder in Xcode project.

This is its own task. Tools:
- **Figma / Sketch** — hand draw, export at 1024
- **Bakery** (Mac App Store, ~$10) — icon-focused design tool
- **IconKitchen** (free web) — generates the whole iOS icon set from one source
- **Commission** — $50–200 on Fiverr for a clean mark

Don't ship with a placeholder.

---

## 10. Submission Checklist

When App Store Connect is unlocked (post D-U-N-S), run through this in order:

- [ ] Create App Store Connect app record (Bundle ID: `dev.pinnacleapp.bjjcompanion`)
- [ ] Paste App Information (name, subtitle, category)
- [ ] Paste Store Listing (promo, description, keywords, URLs, copyright)
- [ ] Set Pricing (Free) + Availability (All countries)
- [ ] Complete App Privacy questionnaire per §4 above
- [ ] Complete Age Rating questionnaire per §5 above (4+)
- [ ] Paste App Review Information per §6 above
- [ ] Upload 1024×1024 icon
- [ ] Upload 3–10 screenshots at 6.9"
- [ ] Archive release build in Xcode, upload via Organizer
- [ ] Wait for build to finish processing (~15–30 min)
- [ ] Attach build to version 1.0
- [ ] Submit for review
- [ ] Expect 24–48 hour review turnaround

---

## Open questions to resolve before submission

1. **App name final:** Is `BJJ Companion` a settled decision or do we want to revisit?
2. **Belt claim in description:** What rank is accurate at submission time?
3. **Icon design:** DIY, commission, or placeholder that you'll improve post-launch?
4. **Screenshot data:** Use real athlete names / real tournaments in screenshots, or synthetic? (Apple doesn't care; your user perception does.)
5. **iPad support:** Ship iPhone-only v1, or include iPad at launch? (iPad = another 3–10 screenshots to create.)
