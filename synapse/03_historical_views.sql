CREATE VIEW pdm.vw_telemetry_deduplicated
AS
WITH source_rows AS (
    SELECT
        MessageId,
        MachineId,
        EventTime,
        TemperatureC,
        VibrationMmS,
        PressureBar,
        CycleTimeS,
        RunningHours,
        Status,
        IoTHubDeviceId
    FROM OPENROWSET(
        BULK 'telemetry/**/*.parquet',
        DATA_SOURCE = 'HuskyCuratedLake',
        FORMAT = 'PARQUET'
    ) WITH (
        MessageId VARCHAR(100),
        MachineId VARCHAR(30),
        EventTime DATETIME2,
        TemperatureC FLOAT,
        VibrationMmS FLOAT,
        PressureBar FLOAT,
        CycleTimeS FLOAT,
        RunningHours FLOAT,
        Status VARCHAR(20),
        IoTHubDeviceId VARCHAR(30)
    ) AS r
),
numbered AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY MessageId
            ORDER BY EventTime DESC
        ) AS row_num
    FROM source_rows
)
SELECT
    MessageId,
    MachineId,
    EventTime,
    TemperatureC,
    VibrationMmS,
    PressureBar,
    CycleTimeS,
    RunningHours,
    Status,
    IoTHubDeviceId
FROM numbered
WHERE row_num = 1;
GO


CREATE VIEW pdm.vw_device_daily
AS
SELECT
    CAST(EventTime AS DATE) AS ReadingDate,
    MachineId,
    COUNT(*) AS ReadingCount,
    AVG(TemperatureC) AS AvgTemperatureC,
    MAX(TemperatureC) AS MaxTemperatureC,
    AVG(VibrationMmS) AS AvgVibrationMmS,
    MAX(VibrationMmS) AS MaxVibrationMmS,
    AVG(PressureBar) AS AvgPressureBar,
    SUM(
        CASE WHEN TemperatureC >= 100
             THEN 1 ELSE 0 END
    ) AS CriticalTemperatureReadings,
    SUM(
        CASE WHEN VibrationMmS >= 8
             THEN 1 ELSE 0 END
    ) AS CriticalVibrationReadings
FROM pdm.vw_telemetry_deduplicated
GROUP BY CAST(EventTime AS DATE), MachineId;
GO


CREATE VIEW pdm.vw_fleet_summary
AS
SELECT
    ReadingDate,
    COUNT(DISTINCT MachineId) AS ActiveMachines,
    SUM(ReadingCount) AS TotalReadings,
    SUM(CriticalTemperatureReadings)
        AS CriticalTemperatureReadings,
    SUM(CriticalVibrationReadings)
        AS CriticalVibrationReadings,
    AVG(AvgTemperatureC) AS AvgMachineTemperatureC,
    AVG(AvgVibrationMmS) AS AvgMachineVibrationMmS
FROM pdm.vw_device_daily
GROUP BY ReadingDate;
GO


ALTER VIEW pdm.vw_telemetry_deduplicated
AS
WITH source_rows AS (
    SELECT
        MessageId,
        MachineId,
        EventTime,
        TemperatureC,
        VibrationMmS,
        PressureBar,
        CycleTimeS,
        RunningHours,
        Status,
        IoTHubDeviceId
    FROM OPENROWSET(
        BULK 'telemetry/**',
        DATA_SOURCE = 'HuskyCuratedLake',
        FORMAT = 'PARQUET'
    ) WITH (
        MessageId VARCHAR(100),
        MachineId VARCHAR(30),
        EventTime DATETIME2,
        TemperatureC FLOAT,
        VibrationMmS FLOAT,
        PressureBar FLOAT,
        CycleTimeS FLOAT,
        RunningHours FLOAT,
        Status VARCHAR(20),
        IoTHubDeviceId VARCHAR(30)
    ) AS r
),
numbered AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY MessageId
            ORDER BY EventTime DESC
        ) AS row_num
    FROM source_rows
)
SELECT
    MessageId,
    MachineId,
    EventTime,
    TemperatureC,
    VibrationMmS,
    PressureBar,
    CycleTimeS,
    RunningHours,
    Status,
    IoTHubDeviceId
FROM numbered
WHERE row_num = 1;
