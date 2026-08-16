# Intatis EPUBCheck wrapper

This project-owned launcher exposes the fixed executable name expected by
`DocumentBackendProcessRunner` while delegating EPUB conformance checks to the
unmodified official EPUBCheck distribution.

Runtime layout:

```text
document-runtime/
  bin/intatis-epubcheck
  jre/temurin-21.0.11+10/Contents/Home/bin/java
  lib/epubcheck-5.3.0/
    epubcheck.jar
    lib/*.jar
    LICENSE.txt
    THIRD-PARTY.txt
    licenses/*
```

The wrapper accepts no Intatis-specific command language. A release forwards
the host-owned fixed argv to the architecture root's pinned, self-contained
Temurin JRE 21.0.11+10 via `java -Djava.awt.headless=true -jar ...`.
`/usr/bin/java` remains only as
a compatibility fallback for a user-managed development runtime. A wrapper
under `Intatis.app/Contents/Resources/DocumentRuntime/<architecture>` fails
closed if its bundled JRE is unavailable; it never falls back to system Java.
The development fallback does not satisfy the release validator.
The model cannot choose the executable, JAR, environment, network policy, or
runtime directory.

The local development runtime uses the official W3C release asset:

- release: `w3c/epubcheck` `v5.3.0`
- asset: `epubcheck-5.3.0.zip`
- asset SHA-256:
  `6c07e68584b2e2ce2f89fe06e1246dfead3eb36b46b340e7d93524f29dcff6c5`
- source URL:
  `https://github.com/w3c/epubcheck/releases/download/v5.3.0/epubcheck-5.3.0.zip`

The upstream distribution is intentionally not committed here. A packaged
Intatis release must preserve the distribution's `LICENSE.txt`,
`THIRD-PARTY.txt`, and `licenses/` directory. The architecture-specific Java
runtime, SBOM, license inventory, hashes, and signatures are mandatory inputs
to `scripts/validate-document-runtime.sh` and the App release gate.
