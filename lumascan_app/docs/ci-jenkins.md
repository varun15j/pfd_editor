# Jenkins CI

The `Jenkinsfile` at the repo root checks every pull request before it can be merged:

1. `flutter pub get`
2. `flutter analyze` (must report no issues)
3. `flutter test` (all tests must pass; results are archived as `test-results.json`)
4. `flutter build apk --debug` (the APK is archived on the build)

It runs inside the `ghcr.io/cirruslabs/flutter:3.47.6` Docker image, so the Jenkins agent only needs Docker.

## One-time setup

**Jenkins**
1. Install the plugins: Pipeline, Docker Pipeline, GitHub Branch Source.
2. Add a GitHub credential (a GitHub App, or a token with `repo` scope).
3. New Item → Multibranch Pipeline → Branch Source: GitHub, repository `varun15j/pfd_editor`.
   Keep "Discover pull requests from origin" on. Script path: `Jenkinsfile`.
4. In GitHub → Settings → Webhooks, add `https://<your-jenkins>/github-webhook/` (content type JSON, push and pull request events) so builds start without polling.

**GitHub (makes the check block merging)**
1. Settings → Branches → add a rule (or ruleset) for `design/prototype-polish-hld`.
2. Turn on "Require status checks to pass before merging" and pick the Jenkins check
   (`continuous-integration/jenkins/pr-merge`). It appears in the list after the first PR build.
3. Optionally turn on "Require branches to be up to date before merging".

## Running Jenkins on your PC (docker-compose)

`ci/jenkins/` starts a ready-made Jenkins with the plugins installed, an admin user, the GitHub
credential and the **LumaScan** Multibranch job already created (configuration as code). You need
Docker Desktop running.

1. Create a GitHub fine-grained token for `varun15j/pfd_editor` with read access to Contents,
   Metadata and Pull requests, and read/write access to Commit statuses.
2. In `ci/jenkins`, copy `.env.example` to `.env`, set an admin password and paste the token.
   `.env` is git-ignored.
3. `cd ci/jenkins` then `docker compose up -d --build`.
4. Open http://localhost:8080 and sign in. The LumaScan job scans the repo on start and then every
   5 minutes, building each open PR and reporting its status back to GitHub.

The first build pulls the Flutter image (several GB), so it takes a while.

**Webhook (optional, for instant builds).** GitHub can't reach `localhost`, so expose Jenkins with a
tunnel, e.g. `ngrok http 8080`. Set `JENKINS_URL` in `.env` to the tunnel URL, restart with
`docker compose up -d`, and add `https://<tunnel>/github-webhook/` as the webhook in GitHub. Without
it, the 5-minute scan still checks every PR.
