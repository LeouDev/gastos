# gastos: App Store submission kit

Everything to paste into App Store Connect for version 1.0. The screenshots are in `appstore/screenshots/` (6.9", 1320 × 2868) and the review video is `appstore/review-walkthrough.mp4`.

To regenerate them:
- Screenshots: `scripts/app-store-screenshots.sh`
- Video: `scripts/review-video.sh`

---

## App Information

| Field | Value |
|---|---|
| Name | gastos — money tracker |
| Subtitle (30) | Know where your money goes |
| Primary category | Finance |
| Secondary category | Productivity |
| Content rights | Does not contain, show, or access third-party content |
| Age rating | 4+. Answer "None" to every content question. Unrestricted web access: No. Gambling: No. |
| Copyright | 2026 Leou Alven Comendador |

## Version 1.0: App Store page

**Promotional text (170)**

> Track an expense in seconds, see which wallet or card paid, and know how much you can spend today. Private by design: no ads, no tracking.

**Description**

> gastos is a calm, simple money tracker for people who hate budgeting apps.
>
> Every transaction answers three questions: How much? What was it for? Which wallet paid? Type ₱350, tap Food, tap GCash. Done.
>
> WHERE DID IT GO?
> See your spending by category, then tap one to see which wallet or card paid for it.
>
> WALLETS THAT LOOK LIKE YOURS
> Banks, e-wallets, cash and credit cards as beautiful cards you can style: textures, colors or your own photo. Stack them like Apple Wallet and drag to reorder.
>
> CREDIT CARDS, DONE RIGHT
> A card purchase counts as spending. Paying the card is a transfer, so nothing is counted twice.
>
> YOU CAN SPEND ₱1,023 TODAY
> Your money, minus bills coming up, spread over the days until payday. Tap it to see the math.
>
> BILLS AND SALARY ON AUTOPILOT
> Rent, Netflix, internet and payday are recorded on their dates and shown in Coming Up.
>
> BUDGETS AND INSIGHTS
> Simple monthly budgets per category, spending charts, and how this month compares with last.
>
> CARDS & PASSES
> Keep loyalty cards, memberships, tickets and IDs with their QR codes or barcodes, shown bright and big at the counter.
>
> PRIVATE BY DESIGN
> No account needed. Your data lives on your iPhone, protected by Face ID. Sign in with Apple only if you want to sync your devices. No ads, no trackers, and your data is never sold.
>
> gastos Premium is ₱99 a month, billed by Apple. Have the code GASTOS? Redeem it before subscribing for your first month free. Cancel anytime in Settings.
>
> Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
> Privacy Policy: https://gastos-eta-one.vercel.app/privacy/

**Keywords (100)**

```
budget,expense,tracker,gcash,maya,wallet,peso,spending,bills,credit card,savings,finance,gastos,pera
```

| Field | Value |
|---|---|
| Support URL | https://gastos-eta-one.vercel.app/support/ |
| Marketing URL | https://gastos-eta-one.vercel.app |
| Privacy Policy URL | https://gastos-eta-one.vercel.app/privacy/ |

**In-App Purchases and Subscriptions:** attach **Premium Monthly** to this version. This is the "Add for Review" step.

**Version Release:** choose **Manually release this version**, so you can create the GASTOS custom code after approval and before release.

---

## App Privacy (Data Types)

**Do you or your third-party partners collect data from this app?** Yes. It's only sent when someone chooses Sign in with Apple, to sync their data.

| Data type | Linked to user | Used for tracking | Purpose |
|---|---|---|---|
| Financial Info → Other Financial Info | Yes | No | App Functionality |
| Contact Info → Email Address | Yes | No | App Functionality |
| Identifiers → User ID | Yes | No | App Functionality |

Answer **not collected** for everything else, including:
- **Purchases:** Apple processes the subscription, and gastos doesn't store purchase history.
- **Photos:** card photos stay on the device.
- **Location, Contacts, Browsing, Usage Data, Diagnostics:** none of these are collected.

---

## App Review Information

**Sign-in required:** No. There is no demo account. The app works without an account; Sign in with Apple is optional and only enables sync.

**Notes:**

> gastos is a personal finance tracker. After a short onboarding (3 screens), the app shows a paywall: gastos Premium, ₱99/month auto-renewing subscription (product com.leoudev.gastos.premium.monthly). Please subscribe with your sandbox account to access the app. Restore Subscription is on the same screen.
>
> The "Got the GASTOS code?" button opens Apple's offer code redemption sheet (offer code: GASTOS, first month free for new subscribers). The custom code will be created once the subscription is approved.
>
> After subscribing: tap + to add an expense, income or transfer. Wallets holds bank/e-wallet/cash/credit card cards; Insights shows spending charts.
>
> Account: Sign in with Apple is optional (Settings → Sync). Account deletion is in Settings → Sync → Delete account (visible when signed in); it deletes the account and all synced data from our server and revokes the Sign in with Apple token.
>
> Manage or cancel the subscription: Settings → gastos Premium → Manage subscription.
>
> A walkthrough video of the full flow is attached.

**Attachment:** `review-walkthrough.mp4`

**Contact:** your name, phone and gasto@air-rally.com
