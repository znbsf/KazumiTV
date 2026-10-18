# Public QA signing fixture

`public-test-only.jks` is intentionally PUBLIC, including its signing key. It is
not a secret or an identity credential. Anyone can sign with it. Never trust a
package merely because it carries this certificate; review its source and the
verified CI artifact SHA256. Never use this key for production, accounts,
signature permissions, trusted inter-app access or any other security boundary.

Alias: `public-test-only`. Store/key password: `android`.
Certificate SHA256: `131f00a5a75f3e587ece7ef86a96a21c5971db5717123890121dc55363523ea1`.

Opt in with `kazumiTvPublicTestSigning=true`, `kazumiTv=true` and exact app ID
`com.znbsf.kazumi.fluttertv.remoteqa`. The Gradle overlay rejects other app IDs
and simultaneous production signing. Normal and production signing stay intact.
CI verifies this fingerprint for every ABI. Do not regenerate this fixture per
build. No GitHub Secret or private signing credential is needed.

QA6-r2 starts the fixed-signature sequence. Future same-ID builds with this key
and increasing versionCode can update that sequence. Old QA6 / QA6-r1 used
unrelated ephemeral certificates and cannot be directly overwritten by r2.
Any initial replacement is a separate user-controlled action; this change does
not authorize installation, removal or data deletion.
