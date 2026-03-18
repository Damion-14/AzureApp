IF OBJECT_ID('dbo.api_keys', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.api_keys
    (
        apiKeyId UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        clientId UNIQUEIDENTIFIER NOT NULL,
        keyName NVARCHAR(100) NOT NULL,
        keyHash VARBINARY(32) NOT NULL,
        isActive BIT NOT NULL CONSTRAINT DF_api_keys_isActive DEFAULT 1,
        expiresAt DATETIME2 NULL,
        revokedAt DATETIME2 NULL,
        createdAt DATETIME2 NOT NULL CONSTRAINT DF_api_keys_createdAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_api_keys_clients FOREIGN KEY (clientId) REFERENCES dbo.clients (clientId)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'UX_api_keys_keyHash'
      AND object_id = OBJECT_ID('dbo.api_keys')
)
BEGIN
    CREATE UNIQUE INDEX UX_api_keys_keyHash
        ON dbo.api_keys (keyHash);
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_api_keys_clientId'
      AND object_id = OBJECT_ID('dbo.api_keys')
)
BEGIN
    CREATE INDEX IX_api_keys_clientId
        ON dbo.api_keys (clientId);
END;
GO
