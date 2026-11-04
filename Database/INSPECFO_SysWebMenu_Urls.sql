-- SysWeb2 menu URL mapping for INSPECFO.
-- Run this once after the corresponding SysWebMenu rows have been created.
-- Entry/approval modes are deliberately distinct even when they share one ASPX page.

BEGIN TRANSACTION;

UPDATE dbo.SysWebMenu
SET [Url] = CASE CONVERT(VARCHAR(50), MenuID)
    WHEN '20010' THEN '#'
    WHEN '20011' THEN 'workorder.aspx?type=entry'
    WHEN '20012' THEN 'workorder.aspx?type=approval'
    WHEN '20020' THEN '#'
    WHEN '20021' THEN 'inspection.aspx?type=entry'
    WHEN '20022' THEN 'inspection.aspx?type=approval'
    WHEN '20030' THEN '#'
    WHEN '20031' THEN 'T_DailyLogEmployee.aspx'
    WHEN '20040' THEN '#'
    WHEN '20041' THEN 'meterreading.aspx?type=ELC'
    WHEN '20042' THEN 'meterreading.aspx?type=WTR'
    WHEN '20043' THEN 'meterreading.aspx?type=GAS'
END
WHERE AppID = 'inspecfo'
  AND CONVERT(VARCHAR(50), MenuID) IN
      ('20010','20011','20012','20020','20021','20022',
       '20030','20031','20040','20041','20042','20043');

SELECT MenuID, ParentMenuID, Caption, [Url], AppID, isActive
FROM dbo.SysWebMenu
WHERE AppID = 'inspecfo'
  AND CONVERT(VARCHAR(50), MenuID) IN
      ('20010','20011','20012','20020','20021','20022',
       '20030','20031','20040','20041','20042','20043')
ORDER BY MenuID;

COMMIT TRANSACTION;
