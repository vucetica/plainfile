# Setup Guide: Apple and GitHub

This is the complete, ordered checklist of everything the maintainer sets up by hand before the first release of Plainfile. Part A covers Apple (the Developer portal and App Store Connect). Part B covers GitHub (the repository, Actions, Pages and DNS). Work through the steps in order, because later steps use things created in earlier ones.

Facts used throughout:

| Item | Value |
|---|---|
| App name | Plainfile |
| Bundle ID | `app.plainfile.app` (Debug builds use `app.plainfile.app.debug`, which is never registered or distributed) |
| Team ID | `8594MRU6A8` |
| SKU | `plainfile-macos` |
| Repository | https://github.com/vucetica/plainfile |
| Website | https://plainfile.app |
| Privacy policy | https://plainfile.app/privacy |

The CI side of signing (what each secret is used for, renewal and troubleshooting) is described in [../RELEASE.md](../RELEASE.md).

---

## Part A: Apple

### A1. Apple Developer Program membership

- [ ] Sign in at [developer.apple.com/account](https://developer.apple.com/account) and confirm that the membership is active for team `8594MRU6A8`. If you are not enrolled yet, enroll in the Apple Developer Program (99 USD per year) and wait for the enrollment to be approved.
- [ ] Confirm that you have accepted the latest agreements under **Agreements, Tax, and Banking** in App Store Connect. A free app only needs the Free Apps agreement, which is accepted with the Program License Agreement.

### A2. Register the App ID

- [ ] In the Developer portal, open **Certificates, Identifiers & Profiles, Identifiers**, and click **+**.
- [ ] Choose **App IDs**, then **App**.
- [ ] Platform: **macOS**. Description: `Plainfile`. Bundle ID: **Explicit**, `app.plainfile.app`.
- [ ] Leave every capability turned off. The app uses only the sandbox and user-selected file access, and those are entitlements that need no capability on the App ID.
- [ ] Click **Continue**, then **Register**.

### A3. Create the certificates

You need three certificates. The easiest way is **Xcode, Settings, Accounts**, select your Apple Account, select the team, click **Manage Certificates**, then **+**. You can also create them on the [Certificates page](https://developer.apple.com/account/resources/certificates/list) of the portal with a certificate signing request from Keychain Access.

- [ ] **Developer ID Application**: signs the notarized download on GitHub Releases. In an organization team, only the Account Holder can create it.
- [ ] **Apple Distribution**: signs the app for the Mac App Store.
- [ ] **Mac Installer Distribution**: signs the `.pkg` that is uploaded to App Store Connect.
- [ ] Check that all three appear in **Keychain Access, login, My Certificates**, each with its private key underneath.

Export each one as `.p12` later, in step B3. The steps for exporting are in [../RELEASE.md](../RELEASE.md#one-time-setup).

### A4. Create the Mac App Store provisioning profile

- [ ] In the portal, open **Profiles** and click **+**.
- [ ] Under **Distribution**, choose **Mac App Store Connect**.
- [ ] Choose the App ID `app.plainfile.app`.
- [ ] Choose the **Apple Distribution** certificate from step A3.
- [ ] Name the profile `Plainfile App Store`, click **Generate**, then **Download**.

The project needs no Developer ID provisioning profile, because Plainfile uses no advanced capabilities such as iCloud.

### A5. Create the App Store Connect API key

- [ ] In [App Store Connect](https://appstoreconnect.apple.com), open **Users and Access, Integrations, App Store Connect API, Team Keys**.
- [ ] Click **Generate API Key** (or **+**). Name: `GitHub Actions CI`. Access: **App Manager**.
- [ ] Write down the **Key ID** and the **Issuer ID** (shown at the top of the page).
- [ ] Click **Download API Key** to save `AuthKey_XXXX.p8`. You can download it only once, so keep it somewhere safe.

### A6. Create the app record

- [ ] In App Store Connect, open **Apps**, click **+**, then **New App**.
- [ ] Fill in the form:

  | Field | Value |
  |---|---|
  | Platforms | macOS |
  | Name | Plainfile |
  | Primary Language | English (U.S.) |
  | Bundle ID | `app.plainfile.app` |
  | SKU | `plainfile-macos` |
  | User Access | Full Access |

- [ ] Click **Create**.

The app name must be unique on the App Store. If App Store Connect says the name "Plainfile" is already in use, pick a name such as "Plainfile Editor" for the store listing. The name on the Mac (`CFBundleDisplayName`) can stay "Plainfile".

### A7. App Information

- [ ] Open the app, then **General, App Information**.
- [ ] **Category**: Primary **Developer Tools**, Secondary **Productivity**.
- [ ] **Content Rights**: choose that the app **does not contain, show, or access third-party content**.
- [ ] **Privacy Policy URL** (under App Privacy, or in App Information depending on the page layout): `https://plainfile.app/privacy`. The website must be live first (see Part B), or Apple may reject the submission.

### A8. Pricing and Availability

- [ ] Open **Pricing and Availability**.
- [ ] Set the price to **Free** (USD 0.00).
- [ ] Under availability, choose **all countries or regions**.

### A9. App Privacy

- [ ] Open **App Privacy** and click **Get Started**.
- [ ] Answer **No, we do not collect data from this app**. The label then reads **Data Not Collected**.
- [ ] Click **Publish**.

### A10. Age Rating

- [ ] In App Information, find **Age Rating** and click **Edit** (or **Set Up Age Ratings**).
- [ ] Answer **None** or **No** to every question.
- [ ] The result is **4+**.

### A11. Version page

- [ ] Open the macOS version (**1.0 Prepare for Submission**).
- [ ] Upload the screenshots from `distribution/screenshots/` (see [screenshots.md](screenshots.md)).
- [ ] Copy the promotional text, description and keywords from [metadata.md](metadata.md).
- [ ] **Support URL**: `https://plainfile.app`. **Marketing URL**: `https://plainfile.app`.
- [ ] **Copyright**: `2026 Aleksandar Vucetic`.
- [ ] Under **App Review Information**, turn off **Sign-in required** and add your contact details.

### A12. Export compliance

Nothing to do by hand. `Info.plist` sets `ITSAppUsesNonExemptEncryption` to `NO`, so App Store Connect answers the encryption question automatically for every uploaded build.

### A13. First submission

Before this step, finish Part B up to and including B3 (secrets) and B7 (Pages), so CI can sign and upload, and the privacy policy is online.

- [ ] Make the first release on GitHub (step B13). Pushing the tag `v1.0.0` starts the `app-store` job, which uploads the build.
- [ ] Wait until the build has finished processing. It appears in App Store Connect under **TestFlight** and on the version page, usually within 15 to 60 minutes. Apple sends an email when processing is done.
- [ ] On the version page, under **Build**, click **+** and select the uploaded build.
- [ ] Paste the text from [review-notes.md](review-notes.md) into **Notes** under App Review Information.
- [ ] Under **Version Release**, choose **Manually release this version**, so you can check everything before the app goes live.
- [ ] Click **Add for Review**, then **Submit to App Review**.
- [ ] Watch the status. If the app is rejected, read the message in the Resolution Center, fix the issue, and submit again.
- [ ] After approval, click **Release This Version**.

### A14. After approval

- [ ] Copy the App Store URL (for example `https://apps.apple.com/app/plainfile/id1234567890`) from the app's page in App Store Connect (**App Information, View on App Store**).
- [ ] In `docs/index.html`, find the `APP_STORE_URL` comment, replace the `#download` link of the Mac App Store button with the real URL, and remove the comment.
- [ ] In `README.md`, replace "Mac App Store (coming soon)" with a link to the App Store page.
- [ ] Add or update the App Store link in `.github/FUNDING.yml`.
- [ ] Open a pull request with these changes and merge it.

---

## Part B: GitHub

### B1. Rename the default branch to `main`

The workflows, the documentation and the branch protection all use `main`.

- [ ] On GitHub, open **Settings, General**. Under **Default branch**, click the rename (pencil) button, rename `master` to `main`, and confirm.
- [ ] On your Mac, update the local clone:
  ```bash
  git branch -m master main
  git fetch origin
  git branch -u origin/main main
  git remote set-head origin -a
  ```
  The first command renames your local branch. Skip it if your local branch is already called `main`.

### B2. Repository variable

- [ ] Open **Settings, Secrets and variables, Actions, Variables**, click **New repository variable**, and add `TEAM_ID` with the value `8594MRU6A8`.

### B3. Repository secrets

Open **Settings, Secrets and variables, Actions, Secrets** and add each secret with **New repository secret**. For every file, copy the base64 text to the clipboard with `base64 -i <file> | pbcopy` and paste it into the secret's value. Delete each `.p12` file once its secret is saved, because it contains a private key.

| Secret | How to produce it |
|---|---|
| `KEYCHAIN_PASSWORD` | Any random string, for example the output of `openssl rand -base64 24`. |
| `ASC_KEY_ID` | The Key ID from step A5 (10 characters). |
| `ASC_ISSUER_ID` | The Issuer ID from step A5 (a UUID). |
| `ASC_KEY_BASE64` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` with the key file from step A5. |
| `DEVID_CERT_BASE64` | Export the Developer ID Application certificate and its private key from Keychain Access as `devid.p12`, then `base64 -i devid.p12 \| pbcopy`. |
| `DEVID_CERT_PASSWORD` | The password you chose when you exported `devid.p12`. |
| `DIST_CERT_BASE64` | Export the Apple Distribution certificate and its key as `dist.p12`, then `base64 -i dist.p12 \| pbcopy`. |
| `DIST_CERT_PASSWORD` | The password you chose for `dist.p12`. |
| `INSTALLER_CERT_BASE64` | Export the Mac Installer Distribution certificate and its key as `installer.p12`, then `base64 -i installer.p12 \| pbcopy`. |
| `INSTALLER_CERT_PASSWORD` | The password you chose for `installer.p12`. |
| `PROVISIONING_PROFILE_BASE64` | `base64 -i Plainfile_App_Store.provisionprofile \| pbcopy` with the profile from step A4. |

- [ ] All 11 secrets are saved.

### B4. Actions permissions

- [ ] Open **Settings, Actions, General**.
- [ ] Under **Actions permissions**, allow all actions and reusable workflows, or at least the actions the workflows use (`actions/*`, `maxim-lobanov/setup-xcode` and `softprops/action-gh-release`).
- [ ] Under **Workflow permissions**, you can leave the default **Read repository contents and packages permissions**. Read and write permission is not required, because `release.yml` asks for `contents: write` itself, which it needs to create releases.
- [ ] Leave **Allow GitHub Actions to create and approve pull requests** turned off. The workflows do not need it.

### B5. Check the workflows

- [ ] Open **Actions** and confirm that `build.yml` ran green on the latest push to `main`.
- [ ] Run `release.yml` by hand (**Actions, Build, Notarize & Release, Run workflow** on `main`). Both jobs should succeed. The `app-store` job uploads a build to App Store Connect, which is fine, because the build is only used if you select it.
- [ ] Download the `Plainfile.dmg` artifact, open it, drag the app to Applications, and launch it. macOS should open it without a warning, which shows that notarization works.

### B6. Pages

- [ ] Open **Settings, Pages**.
- [ ] Under **Build and deployment**, choose **Deploy from a branch**, then the branch `main` and the folder `/docs`, and click **Save**.
- [ ] Under **Custom domain**, enter `plainfile.app` and click **Save**. The `docs/CNAME` file already contains the same domain.
- [ ] Wait until GitHub has issued the TLS certificate for the domain (this can take up to an hour after DNS works), then turn on **Enforce HTTPS**.

### B7. DNS at the domain registrar

Add these records for `plainfile.app` at the registrar or DNS provider. Remove any other A, AAAA or CNAME records for the apex and for `www` first, such as a parking page.

| Type | Name | Value |
|---|---|---|
| A | `@` | `185.199.108.153` |
| A | `@` | `185.199.109.153` |
| A | `@` | `185.199.110.153` |
| A | `@` | `185.199.111.153` |
| AAAA | `@` | `2606:50c0:8000::153` |
| AAAA | `@` | `2606:50c0:8001::153` |
| AAAA | `@` | `2606:50c0:8002::153` |
| AAAA | `@` | `2606:50c0:8003::153` |
| CNAME | `www` | `vucetica.github.io` |

- [ ] Check the records with `dig plainfile.app +short` and `dig www.plainfile.app +short`.
- [ ] Open https://plainfile.app and https://plainfile.app/privacy in a browser.

### B8. Verify the domain

Verifying the domain stops other GitHub accounts from publishing a Pages site on it if your Pages site is ever turned off.

- [ ] Open your **account** settings (your profile picture, **Settings**), then **Pages**, and click **Add a domain**.
- [ ] Enter `plainfile.app`. GitHub shows a TXT record.
- [ ] Add the TXT record at the registrar, wait for it to appear, and click **Verify**.

### B9. Features

- [ ] Open **Settings, General, Features**.
- [ ] **Issues**: on.
- [ ] **Discussions**: on. Then open the **Discussions** tab, and keep or create the categories **Q&A**, **Ideas** and **General**. Remove the categories you do not want.
- [ ] **Wiki**: off. The documentation lives in the repository.
- [ ] **Projects**: optional. Turn it off if you do not plan to use it.

### B10. Security

- [ ] Open **Settings, Code security** (called **Security** or **Code security and analysis** on some accounts).
- [ ] **Private vulnerability reporting**: on. `SECURITY.md` points people to it.
- [ ] **Dependabot alerts**: on.
- [ ] **Dependabot security updates**: on.
- [ ] **Secret scanning**: on.
- [ ] **Push protection**: on.

### B11. Branch protection ruleset for `main`

- [ ] Open **Settings, Rules, Rulesets**, click **New ruleset**, then **New branch ruleset**.
- [ ] Name: `main`. Enforcement status: **Active**.
- [ ] Target branches: **Add target, Include default branch**.
- [ ] Turn on **Restrict deletions**.
- [ ] Turn on **Require a pull request before merging**.
- [ ] Turn on **Require status checks to pass**, click **Add checks**, and add **Build (macOS)**. The check name only appears in the list after `build.yml` has run at least once.
- [ ] Turn on **Block force pushes**.
- [ ] Optionally add yourself to the bypass list, so you can still push a fix in an emergency.
- [ ] Click **Create**.

### B12. Repository profile

- [ ] On the repository's main page, click the gear next to **About**.
- [ ] Description: `A native macOS editor for plain text, code, Markdown and CSV.`
- [ ] Website: `https://plainfile.app`
- [ ] Topics: `macos`, `swift`, `swiftui`, `appkit`, `text-editor`, `markdown`, `csv`, `open-source`
- [ ] Open **Settings, General, Social preview**, click **Edit, Upload an image**, and choose `docs/og-image.png`.

### B13. Make the repository public

Do this last, after everything above works.

- [ ] Check that no secrets are in the git history. For example, run `git log -p | grep -iE "BEGIN (RSA |EC )?PRIVATE KEY|AuthKey_|\.p12|password"` and look through the results, or scan with a tool such as [gitleaks](https://github.com/gitleaks/gitleaks) (`gitleaks detect`). If you find a secret, revoke it at its source and remove it from the history before you go on.
- [ ] Check that no `.p8`, `.p12` or `.provisionprofile` file is tracked: `git ls-files | grep -E "\.(p8|p12|provisionprofile)$"` should print nothing.
- [ ] Open **Settings, General, Danger Zone, Change repository visibility**, and choose **Public**.

### B14. First release

The release process is the one in the **Releasing** section of [CLAUDE.md](../../CLAUDE.md).

- [ ] Check that `MARKETING_VERSION` in `project.yml` is `1.0.0`. Never edit `CURRENT_PROJECT_VERSION`, because CI sets it.
- [ ] Check that `CHANGELOG.md` has the `## [1.0.0]` section with today's date and an empty `## [Unreleased]` section above it.
- [ ] Open a pull request with any remaining changes, wait for **Build (macOS)** to pass, and merge it.
- [ ] Tag the merge commit and push the tag:
  ```bash
  git checkout main && git pull
  git tag -a v1.0.0 -m "v1.0.0: first public release"
  git push origin v1.0.0
  ```
- [ ] Watch `release.yml` in **Actions**. The `notarized-app` job attaches `Plainfile.dmg` and `Plainfile.zip` to the GitHub Release for `v1.0.0`, and the `app-store` job uploads the build to App Store Connect.
- [ ] Check that https://github.com/vucetica/plainfile/releases/latest shows `v1.0.0` with both files, then continue with step A13.
