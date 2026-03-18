IF OBJECT_ID('dbo.clients', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.clients
    (
        clientId UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        tenantId NVARCHAR(100) NOT NULL,
        name NVARCHAR(200) NOT NULL,
        isActive BIT NOT NULL CONSTRAINT DF_clients_isActive DEFAULT 1,
        createdAt DATETIME2 NOT NULL CONSTRAINT DF_clients_createdAt DEFAULT SYSUTCDATETIME(),
        updatedAt DATETIME2 NOT NULL CONSTRAINT DF_clients_updatedAt DEFAULT SYSUTCDATETIME()
    );
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'UX_clients_tenantId'
      AND object_id = OBJECT_ID('dbo.clients')
)
BEGIN
    CREATE UNIQUE INDEX UX_clients_tenantId
        ON dbo.clients (tenantId);
END;
GO

IF OBJECT_ID('dbo.client_identities', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.client_identities
    (
        identityType NVARCHAR(50) NOT NULL,
        externalId NVARCHAR(200) NOT NULL,
        clientId UNIQUEIDENTIFIER NOT NULL,
        createdAt DATETIME2 NOT NULL CONSTRAINT DF_client_identities_createdAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_client_identities PRIMARY KEY (identityType, externalId),
        CONSTRAINT FK_client_identities_clients FOREIGN KEY (clientId) REFERENCES dbo.clients (clientId)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_client_identities_clientId'
      AND object_id = OBJECT_ID('dbo.client_identities')
)
BEGIN
    CREATE INDEX IX_client_identities_clientId
        ON dbo.client_identities (clientId);
END;
GO
