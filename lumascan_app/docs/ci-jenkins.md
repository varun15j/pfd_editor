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
