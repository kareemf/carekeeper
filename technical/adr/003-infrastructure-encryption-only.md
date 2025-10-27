# ADR 003: Infrastructure-Level Encryption Only

## Status
Accepted

## Context
CareKeeper stores sensitive care data (feeding times, medical notes, locations). Initial design considered using CloudKit's `encryptedValues` for field-level encryption. However, the core feature is **collaborative care tracking** - multiple caregivers need read/write access to shared carees.

CloudKit's `encryptedValues` uses the owner's private key for encryption, meaning:
- Only the owner can decrypt encrypted fields
- Share participants see `nil` for encrypted fields
- Incompatible with CloudKit sharing

## Decision
Use **infrastructure-level encryption only**:
1. **Device encryption**: iOS File Protection Complete (automatic when device locked)
2. **Transit encryption**: CloudKit TLS (automatic)
3. **At-rest encryption**: CloudKit server-side encryption (automatic)
4. **NO field-level encryption**: Avoid `CKRecord.EncryptedValues`

All fields (notes, locations, names) stored in plaintext CloudKit fields accessible to share participants.

## Consequences

### Positive
- **Sharing works**: All participants can read/write shared caree data
- **Simpler code**: No encryption/decryption logic in app
- **Industry standard**: Same approach as iCloud Notes, Reminders, shared albums
- **Better UX**: No "encrypted fields unavailable" errors for participants
- **Apple's infrastructure**: Enterprise-grade encryption managed by Apple

### Negative
- **No end-to-end encryption**: Apple (and government subpoenas) can access data
- **Trust Apple**: Relies on Apple's security practices
- **No granular control**: Can't encrypt specific fields (e.g., medical notes)
- **Regulatory limitations**: Not suitable for HIPAA or similar compliance (out of scope)

### Security Mitigations
- **iCloud account security**: Protected by user's Apple ID + 2FA
- **Explicit share acceptance**: Users must accept shares, can't be added silently
- **Permission management**: Owner can revoke participant access
- **Device encryption**: Data protected when device locked
- **Future enhancement**: Could add app-level Face ID lock for extra protection

### Alternatives Considered
1. **Use encryptedValues for sensitive fields**:
   - ❌ Breaks CloudKit sharing (participants can't see data)
   - ❌ Defeats core collaborative feature

2. **Implement custom end-to-end encryption**:
   - ❌ Complex key management (key distribution, recovery)
   - ❌ Breaks CloudKit queries (can't search encrypted fields)
   - ❌ High development/maintenance cost
   - ❌ Out of scope for v1

3. **Don't use CloudKit sharing, use manual sync**:
   - ❌ Reinventing CloudKit infrastructure
   - ❌ Significantly more complex
   - ❌ Worse UX (manual participant management)

## Related
- CloudKit sharing implementation (Phase 2.2)
- Security & Privacy section in README.md
- Future consideration: HIPAA compliance (would require separate architecture)
