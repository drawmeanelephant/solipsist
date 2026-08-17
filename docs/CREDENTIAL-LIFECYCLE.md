# Publish Credential Lifecycle & Security Design Specification

**Status:** Approved Design Spec (Issue #60 / Roadmap M8 Publish)  
**Author:** draw me an elephant / uncle-gravity  
**Target:** macOS App Sandbox / Boris Publishing Targets  

---

## 1. Executive Summary & Security Posture

Solipsist is a native macOS workstation that coordinates and broadcasts Boris publications. In **M8 (Publish)**, Solipsist invokes publication flows for:
1. **Standard.site**: OAuth tokens / App passwords.
2. **Nostr**: Private relay signing keys via `--key-stdin`.
3. **GitHub Pages**: Boris-owned workflow evidence inspection.

### The Zero-Leak Invariant
Secrets (API tokens, private keys, passwords) **must never**:
- Appear in process arguments (`argv` / `Process.arguments`).
- Appear in process environment variables (`env` / `Process.environment`).
- Be logged to stdout, stderr, system logs (`os_log`), or crash dumps.
- Be persisted to insecure application storage (e.g. `UserDefaults`, `Info.plist`, or unencrypted files).
- Remain in heap memory after use.

All secrets provided to child compiler processes are streamed strictly over **ephemeral stdin pipes** and wiped from memory immediately upon completion of the write.

---

## 2. Threat Model & Boundaries

| Threat Vector | Mitigation |
|---|---|
| **Process Inspection (`ps`, `pgrep`, `top`)** | Secrets are never passed in `argv` or command-line flags. Boris CLI reads keys via `--key-stdin`. |
| **Environment Variable Snooping** | Secrets are never injected into child process `environment` dictionaries. |
| **Crash Dumps & Core Memory Leaks** | Secrets are held in heap-allocated `SecureBuffer` instances that explicitly zero memory on deallocation using `memset_s`. String interpolation is redacted via `CustomStringConvertible`. |
| **Disk Forensics / Unencrypted Configs** | No plaintext keys are written to workspace metadata, `.plist` files, or cache directories. Long-term persistence is restricted exclusively to Apple's Secure Enclave / macOS Keychain (`kSecClassGenericPassword`). |
| **Shoulder Surfing / Unintended Persistence** | "Remember in Keychain" is an explicit user opt-in toggle per target. Default mode is **Ephemeral Session Mode** (memory-only, wiped on quit or publish completion). |

---

## 3. Credential Lifecycle Architecture

```
                                 ┌───────────────────────────┐
                                 │     User Input Prompt     │
                                 │  (Standard.site / Nostr)  │
                                 └─────────────┬─────────────┘
                                               │
                                 ┌─────────────▼─────────────┐
                                 │       SecureBuffer        │
                                 │ (Fixed-capacity [UInt8])  │
                                 └─────────────┬─────────────┘
                                               │
                    ┌──────────────────────────┴──────────────────────────┐
                    │                                                     │
   [Remember in Keychain = true]                         [Remember in Keychain = false]
                    │                                                     │
                    ▼                                                     ▼
     ┌─────────────────────────────┐                       ┌─────────────────────────────┐
     │      macOS Keychain         │                       │    EphemeralSecretStore     │
     │ (kSecClassGenericPassword)  │                       │   (In-Memory Thread-Safe)   │
     └──────────────┬──────────────┘                       └──────────────┬──────────────┘
                    │                                                     │
                    └──────────────────────────┬──────────────────────────┘
                                               │
                                               ▼
                                 ┌───────────────────────────┐
                                 │     SecretProviding       │
                                 │      (Seam Contract)      │
                                 └─────────────┬─────────────┘
                                               │
                                               ▼
                                 ┌───────────────────────────┐
                                 │    StdinSecretWriter      │
                                 │  • Streams to stdin pipe  │
                                 │  • Flushes & closes (EOF) │
                                 │  • Wipes buffer in memory │
                                 └─────────────┬─────────────┘
                                               │
                                               ▼
                                 ┌───────────────────────────┐
                                 │   Boris Child Process     │
                                 │ (Reads stdin, e.g. Nostr) │
                                 └───────────────────────────┘
```

---

## 4. Components & Responsibilities

### 4.1. `SecureBuffer` (`Sources/Security/SecureBuffer.swift`)
- Holds raw byte sequences (`[UInt8]`) allocated in memory.
- Implements `CustomStringConvertible` / `CustomDebugStringConvertible` returning `<SecureBuffer count=N>` to prevent accidental logging.
- Uses `memset_s` on Darwin to guarantee memory is overwritten with zeros upon `deinit` or explicit `wipe()`, preventing compiler dead-store elimination.

### 4.2. `KeychainStore` (`Sources/Security/KeychainStore.swift`)
- Wraps Apple `Security.framework` generic password APIs (`kSecClassGenericPassword`).
- Uses service name `dev.drawmeanelephant.solipsist` and account name matching target identifier (e.g. `nostr`, `standard.site`).
- Protected by macOS App Sandbox entitlements.

### 4.3. `EphemeralSecretStore` (`Sources/Security/EphemeralSecretStore.swift`)
- In-memory thread-safe dictionary holding `SecureBuffer` items.
- Supports `consumeSecret(for:)` which retrieves and immediately removes the item from the dictionary.
- Supports `wipeAll()` which explicitly zeroes every active buffer and clears the dictionary on session end or app termination.

### 4.4. `StdinSecretWriter` (`Sources/Security/StdinSecretWriter.swift`)
- Writes bytes directly to the child process's `standardInput` file handle via POSIX `write()`.
- Appends trailing newline (`0x0A`) for line-oriented stdin parsers.
- Closes the write descriptor to send `EOF` so the child process completes reading immediately.
- Invokes `wipe()` on the buffer immediately after transmission.

### 4.5. `PublishCredentialManager` (`Sources/Security/PublishCredentialManager.swift`)
- Orchestrates between `KeychainStore` and `EphemeralSecretStore`.
- Implements `SecretProviding` protocol seam:
  ```swift
  public protocol SecretProviding: Sendable {
      func provideSecret(for target: String) -> SecureBuffer?
  }
  ```
- When "Remember in Keychain" is toggled on: writes to Keychain and clears ephemeral cache.
- When "Remember in Keychain" is toggled off: writes to ephemeral store and deletes any existing Keychain entry.

---

## 5. Publishing Target Specification

### Standard.site (`PublishTargets.standardSite`)
- **Credential:** App password / OAuth bearer token.
- **Delivery:** Stdin authentication handshake.
- **Persistence:** Configurable ("Remember in Keychain" default: false).

### Nostr (`PublishTargets.nostr`)
- **Credential:** `nsec` / 32-byte hex private key.
- **Delivery:** `boris publish nostr --key-stdin` (reads key bytes from stdin pipe until EOF).
- **Persistence:** Configurable ("Remember in Keychain" default: false).

### GitHub Pages (`PublishTargets.githubPages`)
- **Credential:** Solipsist does not require GitHub personal access tokens or credentials for local harness operation. Proof packs and `.nojekyll` workflows are Boris-managed and published through GitHub Actions in the user's repository.

---

## 6. Verification Gate & Test Strategy

Unit tests in `Tests/ContractTests/SecurityTests.swift` verify:
1. **Memory Redaction & Zeroing:** `SecureBuffer` redacts string interpolation and zeroes out buffer memory after `wipe()`.
2. **Ephemeral Isolation:** Secrets in `EphemeralSecretStore` are accessible during the session, wiped on consumption/replacement, and cleared on `wipeAll()`.
3. **Keychain CRUD & Toggle:** Secrets transition cleanly between Keychain and Ephemeral mode based on user preference.
4. **Stdin Pipe Streaming:** `StdinSecretWriter` streams raw bytes to an active `Pipe` file handle, sends EOF, and zeroes the source buffer without leaking into system logs or state stores.
