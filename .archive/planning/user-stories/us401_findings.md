# Findings: US-401 - NetworkActor Foundation

## Technical Discoveries

### Swift 6.2 Actor Patterns
- Actors provide automatic thread-safe isolation for mutable state
- URLSession can be stored in actor with nonisolated(unsafe) when needed
- All async functions in actor are automatically isolated

### URLSession Configuration
- URLSessionConfiguration.default provides baseline
- timeoutIntervalForRequest: 30s for individual requests
- Custom User-Agent: "SwiftWing/1.0 iOS/26.0"

### Keychain Access Pattern
- deviceId should be stored from Epic 1 foundation
- Access via Security framework
- Use kSecClassGenericPassword for storage

### Multipart Form Data
- Content-Type: multipart/form-data; boundary=<UUID>
- Image data encoded with proper MIME type
- Boundary separator between form parts

## API Response Format
```json
{
  "jobId": "uuid-string",
  "streamUrl": "https://talaria.example.com/v3/stream/uuid"
}
```

## Error Handling Strategy
- NetworkError.noConnection - No internet
- NetworkError.timeout - Request timeout
- NetworkError.serverError(Int) - HTTP error codes
- NetworkError.invalidResponse - Parse failure

## Architecture Decisions

### Actor vs. Class
**Decision:** Use actor
**Rationale:**
- Swift 6.2 requires thread-safe network operations
- Actor provides automatic isolation
- Prevents data races on URLSession/deviceId

### Error Enum vs. Throwing NSError
**Decision:** Custom NetworkError enum
**Rationale:**
- Type-safe error handling
- Clear error cases for UI
- Better Swift concurrency integration

## References
- Swift 6.2 Concurrency: Actor isolation patterns
- URLSession: Modern async/await APIs
- Talaria API: POST /v3/jobs/scans endpoint
