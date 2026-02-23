IF OBJECT_ID('dbo.operations', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.operations
    (
        operationId UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        tenantId NVARCHAR(100) NOT NULL,
        idempotencyKey NVARCHAR(200) NOT NULL,
        requestHash VARBINARY(32) NOT NULL,
        status NVARCHAR(20) NOT NULL,
        resourceType NVARCHAR(50) NOT NULL,
        resourceId NVARCHAR(200) NOT NULL,
        errorCode NVARCHAR(100) NULL,
        errorMessage NVARCHAR(2000) NULL,
        createdAt DATETIME2 NOT NULL CONSTRAINT DF_operations_createdAt DEFAULT SYSUTCDATETIME(),
        updatedAt DATETIME2 NOT NULL CONSTRAINT DF_operations_updatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_operations_status CHECK (status IN ('accepted', 'processing', 'succeeded', 'failed'))
    );
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'UX_operations_tenant_idempotency'
      AND object_id = OBJECT_ID('dbo.operations')
)
BEGIN
    CREATE UNIQUE INDEX UX_operations_tenant_idempotency
        ON dbo.operations (tenantId, idempotencyKey);
END;
GO

IF OBJECT_ID('dbo.resource_snapshots', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.resource_snapshots
    (
        tenantId NVARCHAR(100) NOT NULL,
        resourceType NVARCHAR(50) NOT NULL,
        resourceId NVARCHAR(200) NOT NULL,
        snapshotJson NVARCHAR(MAX) NOT NULL,
        etag ROWVERSION NOT NULL,
        updatedAt DATETIME2 NOT NULL CONSTRAINT DF_resource_snapshots_updatedAt DEFAULT SYSUTCDATETIME()
    );
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'UX_resource_snapshots_tenant_type_id'
      AND object_id = OBJECT_ID('dbo.resource_snapshots')
)
BEGIN
    CREATE UNIQUE INDEX UX_resource_snapshots_tenant_type_id
        ON dbo.resource_snapshots (tenantId, resourceType, resourceId);
END;
GO
