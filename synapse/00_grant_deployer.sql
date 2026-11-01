-- =====================================================================
-- 00_grant_deployer.sql  (Lesson 19B)
-- One-time bootstrap, run BY HAND by the Synapse Entra admin.
-- NOT in deploy/synapse-manifest.txt: the pipeline must never run this,
-- because the deployer identity must not be able to grant itself rights.
-- Contains no secrets: only names and permissions.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Script 1. Run with "Use database: master"
-- Creates a server login for the GitHub deployer service principal
-- (sp-husky-pdm-dev), using its Entra ID identity. No password.
-- ---------------------------------------------------------------------
CREATE LOGIN [sp-husky-pdm-dev] FROM EXTERNAL PROVIDER;

-- ---------------------------------------------------------------------
-- Script 2. Run with "Use database: HuskyPDMDev"
-- Maps the login to a database user and grants least privilege.
-- No db_owner.
-- ---------------------------------------------------------------------
CREATE USER [sp-husky-pdm-dev] FROM LOGIN [sp-husky-pdm-dev];

GRANT CREATE VIEW TO [sp-husky-pdm-dev];                         -- create new views
GRANT ALTER ON SCHEMA::pdm TO [sp-husky-pdm-dev];                -- change objects in pdm only
GRANT SELECT ON SCHEMA::pdm TO [sp-husky-pdm-dev];               -- lets the tests read the views
GRANT ADMINISTER DATABASE BULK OPERATIONS TO [sp-husky-pdm-dev]; -- OPENROWSET over the lake
GRANT REFERENCES ON DATABASE SCOPED CREDENTIAL::[HuskyLakeIdentity]
      TO [sp-husky-pdm-dev];                                     -- use the lake credential, not change it

-- ---------------------------------------------------------------------
-- Verify (run in HuskyPDMDev). Expect exactly 6 rows, all GRANT:
-- CONNECT, CREATE VIEW, ADMINISTER DATABASE BULK OPERATIONS,
-- ALTER (SCHEMA), SELECT (SCHEMA), REFERENCES (DATABASE_SCOPED_CREDENTIAL)
-- ---------------------------------------------------------------------
SELECT p.permission_name, p.class_desc, p.state_desc
FROM sys.database_permissions p
JOIN sys.database_principals u ON p.grantee_principal_id = u.principal_id
WHERE u.name = 'sp-husky-pdm-dev';