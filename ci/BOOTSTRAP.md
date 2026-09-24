# One-time CI bootstrap (2 minutes)

GitHub App tokens may not create files under `.github/workflows/`, so this one
file must be created with your account. After that, every push builds a signed,
verified APK automatically.

1. Copy the full contents of `ci/build-apk.yml` (open it on GitHub and click
   the copy button, or open the Raw view and select-all/copy).
2. Open this link — it creates the file with the path prefilled on branch
   `arena/01a0d452-linewise`:

   https://github.com/SpotVibeapp/Linewise/new/arena/01a0d452-linewise?filename=.github%2Fworkflows%2Fbuild-apk.yml

3. Paste the YAML as the file contents and press "Commit changes".
4. Tell the agent "done" — it will then watch the run, verify the APK
   (package, version, signature, zipalign, SHA-256) and deliver it.

Alternative (local git):

    git checkout arena/01a0d452-linewise
    mkdir -p .github/workflows
    cp ci/build-apk.yml .github/workflows/build-apk.yml
    git commit -am "ci: add build workflow"
    git push
