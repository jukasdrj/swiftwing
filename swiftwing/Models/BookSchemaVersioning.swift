import SwiftData

/// Schema versioning for Book model
/// Enables safe, incremental model evolution without data loss
enum BookSchemaV1: VersionedSchema {
    static let versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Book.self]
    }
}

/// Migration plan for Book schema evolution
/// Currently single-version (v1). Future versions add stages here.
enum BookMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BookSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // No migrations yet — v1 is the initial schema
        []
    }
}
