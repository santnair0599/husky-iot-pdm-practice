-- =====================================================================
-- 00_bootstrap_test.sql  (Lesson 18C, Test environment)
-- One-time bootstrap, run BY HAND by the Test Synapse Entra admin.
-- NOT in deploy/synapse-manifest.txt, and deploy_synapse.py refuses it anyway
-- (it contains MASTER KEY / PASSWORD).
-- Replace the two <...> values in your editor; never commit a real password.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Script 1. Run with "Use database: master"
-- ---------------------------------------------------------------------
CREATE DATABASE HuskyPDMTest;
GO

CREATE LOGIN [sp-husky-pdm-test] FROM EXTERNAL PROVIDER;
GO

-- ---------------------------------------------------------------------
-- Script 2. Run with "Use database: HuskyPDMTest"
-- Lake access through the workspace managed identity (no keys).
-- ---------------------------------------------------------------------
CREATE SCHEMA pdm;
GO

CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<STRONG_PRIVATE_PASSWORD>';
GO

CREATE DATABASE SCOPED CREDENTIAL HuskyLakeIdentity
WITH IDENTITY = 'Managed Identity';
GO

CREATE EXTERNAL DATA SOURCE HuskyCuratedLake
WITH (
    LOCATION = 'https://<TEST_STORAGE_ACCOUNT>.dfs.core.windows.net/curated',
    CREDENTIAL = HuskyLakeIdentity
);
GO

-- ---------------------------------------------------------------------
-- Script 3. Run with "Use database: HuskyPDMTest"
-- The Test deployer: same 6 least-privilege grants as Dev, no db_owner.
-- ---------------------------------------------------------------------
CREATE USER [sp-husky-pdm-test] FROM LOGIN [sp-husky-pdm-test];

GRANT CREATE VIEW TO [sp-husky-pdm-test];
GRANT ALTER ON SCHEMA::pdm TO [sp-husky-pdm-test];
GRANT SELECT ON SCHEMA::pdm TO [sp-husky-pdm-test];
GRANT ADMINISTER DATABASE BULK OPERATIONS TO [sp-husky-pdm-test];
GRANT REFERENCES ON DATABASE SCOPED CREDENTIAL::[HuskyLakeIdentity] TO [sp-husky-pdm-test];

-- Verify: exactly 6 rows, all GRANT
SELECT p.permission_name, p.class_desc, p.state_desc
FROM sys.database_permissions p
JOIN sys.database_principals u ON p.grantee_principal_id = u.principal_id
WHERE u.name = 'sp-husky-pdm-test';
