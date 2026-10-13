# Isolated TLS test fixtures

Generated exclusively for loopback tests; these keys are public test material, never application credentials. The CA is trusted only inside a test HttpOverrides zone. It is never installed in a system, emulator, app or production SecurityContext. Valid and wrong-host leaves share a test CA; untrusted is self-signed. Tests must not use badCertificateCallback or disable hostname checks. Certificates last ten years from generation (2026-10-11); regenerate this bounded fixture set before expiry. The CA signing key is not part of the repository.
