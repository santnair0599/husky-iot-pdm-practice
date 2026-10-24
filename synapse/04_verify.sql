-- Daily equipment history
SELECT TOP 20 *
FROM pdm.vw_device_daily
ORDER BY ReadingDate DESC, MachineId;

-- Fleet-level summary
SELECT TOP 20 *
FROM pdm.vw_fleet_summary
ORDER BY ReadingDate DESC;

-- Machines with repeated high vibration
SELECT
    MachineId,
    SUM(CriticalVibrationReadings)
        AS CriticalReadingCount
FROM pdm.vw_device_daily
GROUP BY MachineId
ORDER BY CriticalReadingCount DESC;
