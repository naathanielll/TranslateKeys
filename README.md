# TranslateKeys — free translating keyboard for iPhone (built from Windows)

Type a message with your normal keyboard, tap 🌐 to switch to TranslateKeys, pick a language, tap **Translate**. Your text in the message box is replaced with the translation. The ↩︎ key undoes it.

Translation uses Apple's built-in, on-device translator: no account, no API key, no cost, works offline.

**You need:** a Windows PC, a USB cable for your iPhone, a free GitHub account, a free Apple ID, and an iPhone on **iOS 26 or later** (check Settings → General → About → iOS Version).

---

## Part 1 — Let GitHub build the app for you (about 15 minutes)

1. Unzip `TranslateKeys.zip` on your PC (right-click → Extract All).
2. Go to **github.com** and create a free account (or sign in).
3. Click **+** (top right) → **New repository**.
   - Name: `TranslateKeys`
   - Choose **Public** (unlimited free builds; there's nothing private in this code) — Private also works with a monthly free allowance.
   - Click **Create repository**.
4. On the new repo page, click **uploading an existing file**.
5. Open the unzipped `TranslateKeys` folder. Select **everything inside it** (`.github`, `App`, `Keyboard`, `Shared`, `project.yml`, `README.md`) and drag it all onto the GitHub page. Wait for the files to finish uploading, then click **Commit changes**.
   - Can't see the `.github` folder? In File Explorer: View → Show → Hidden items.
6. Click the **Actions** tab. If it asks, click **I understand my workflows, go ahead and enable them**.
   - You should see **Build TranslateKeys** running (yellow dot). If nothing is running: click **Build TranslateKeys** on the left → **Run workflow** → **Run workflow**.
   - If there's no "Build TranslateKeys" at all, the `.github` folder didn't upload. Click **New workflow → set up a workflow yourself**, open `.github/workflows/build.yml` in Notepad, paste its contents, name the file `build.yml`, and commit.
7. Wait about 5–10 minutes for a **green check**.
   - **Red X?** Click it, click the failed step, copy the red error lines, and send them to Claude to fix.
8. Click the finished run. Under **Artifacts**, download **TranslateKeys-ipa**. Unzip it — you'll get **TranslateKeys.ipa**. That's your app.

## Part 2 — Install it on your iPhone with Sideloadly (about 15 minutes)

9. **Install Apple's helpers on Windows.** Sideloadly needs these to talk to your iPhone:
   - **iTunes** and **iCloud** downloaded from **apple.com** (not the Microsoft Store versions — Sideloadly's site links the right ones).
10. **Install Sideloadly** from **sideloadly.io**.
11. **Connect your iPhone** with the USB cable, unlock it, and tap **Trust This Computer** (enter your passcode).
12. **Open Sideloadly.**
    - Your iPhone should appear at the top.
    - Drag **TranslateKeys.ipa** onto the big IPA icon.
    - Type your **Apple ID email**.
    - Click **Start**, then enter your Apple ID password and the 2‑factor code sent to your devices.
    - Tip: some people use a spare Apple ID for this. Your main one works too.
13. **Turn on Developer Mode** (iPhone): Settings → Privacy & Security → **Developer Mode** → On → Restart → tap **Turn On** after it restarts.
    - The option only appears after step 12.
14. **Trust the app** (iPhone): Settings → General → **VPN & Device Management** → tap your Apple ID → **Trust**.

## Part 3 — Turn on the keyboard (5 minutes)

15. Open the **TranslateKeys** app on your iPhone and tap **Download** next to each language you want. They download for free and work offline.
16. Use the **Try it here** box to make sure translation works.
17. Settings → General → Keyboard → Keyboards → **Add New Keyboard** → **TranslateKeys**.
18. Tap **TranslateKeys** in that list → turn on **Allow Full Access** → **Allow**.
    (Your text never leaves your phone; the keyboard may need this to use Apple's translator.)
19. Try it in Messages: type something → tap/hold 🌐 → **TranslateKeys** → pick a language → **Translate**.

---

## Every 7 days

Free Apple IDs only allow side-loaded apps to run for 7 days. When TranslateKeys stops opening:
plug in your iPhone → open Sideloadly → drag in the same `TranslateKeys.ipa` → **Start**. Your downloaded languages stay.
(Sideloadly's Auto-Refresh option can do this for you over Wi‑Fi while your PC is on.)

## Troubleshooting

- **"Download … first" on the keyboard:** open the TranslateKeys app and tap Download for that language.
- **"Couldn't tell what language this is":** type a few more words; very short text is hard to detect.
- **The keyboard closes itself or does nothing when you tap Translate:** iOS limits how much memory keyboards can use, and Apple's translator may be too heavy in some cases. Send Claude what happened.
- **Sideloadly says "maximum number of apps":** free Apple IDs can have 3 side-loaded apps at a time. Remove another one.
- **Keyboard missing in password fields:** iOS never allows custom keyboards there.

## Languages

Spanish, English, French, Japanese, Korean, Chinese (Simplified and Traditional), Arabic, Hindi, Italian, Portuguese, German, Russian, Vietnamese, Thai, Turkish, Indonesian, Polish, Dutch, Ukrainian — the ones Apple's translator supports.
