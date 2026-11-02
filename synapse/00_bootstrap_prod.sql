-- =====================================================================
-- 00_bootstrap_prod.sql  (Lesson 18C, Prod environment)
-- One-time bootstrap, run BY HAND by the Prod Synapse admin (who created the workspace).
-- NOT in deploy/synapse-manifest.txt, and deploy_synapse.py refuses it anyway
-- (it contains MASTER KEY / PASSWORD).
-- Replace the two <...> values in your editor; never commit a real password.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Script 1. Run with "Use database: master"
-- ---------------------------------------------------------------------
CREATE DATABASE HuskyPDMProd;
GO

CREATE LOGIN [sp-husky-pdm-prod] FROM EXTERNAL PROVIDER;
GO

-- ---------------------------------------------------------------------
-- Script 2. Run with "Use database: HuskyPDMProd"
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
    LOCATION = 'https://<PROD_STORAGE_ACCOUNT>.dfs.core.windows.net/curated',
    CREDENTIAL = HuskyLakeIdentity
);
GO

-- ---------------------------------------------------------------------
-- Script 3. Run with "Use database: HuskyPDMProd"
-- The Prod deployer: same 6 least-privilege grants as Dev, no db_owner.
-- ---------------------------------------------------------------------
CREATE USER [sp-husky-pdm-prod] FROM LOGIN [sp-husky-pdm-prod];

GRANT CREATE VIEW TO [sp-husky-pdm-prod];
GRANT ALTER ON SCHEMA::pdm TO [sp-husky-pdm-prod];
GRANT SELECT ON SCHEMA::pdm TO [sp-husky-pdm-prod];
GRANT ADMINISTER DATABASE BULK OPERATIONS TO [sp-husky-pdm-prod];
GRANT REFERENCES ON DATABASE SCOPED CREDENTIAL::[HuskyLakeIdentity] TO [sp-husky-pdm-prod];

-- Verify: exactly 6 rows, all GRANT
SELECT p.permission_name, p.class_desc, p.state_desc
FROM sys.database_permissions p
JOIN sys.database_principals u ON p.grantee_principal_id = u.principal_id
WHERE u.name = 'sp-husky-pdm-prod';
