IF NOT EXISTS (SELECT * FROM [dbo].[LogAnalyticsIngestControl] WHERE StorageContainerName = 'argvmexports')
BEGIN
    INSERT INTO [dbo].[LogAnalyticsIngestControl] 
    VALUES ('argvmexports', '1901-01-01T00:00:00Z', -1, 'VMsV1', 'ARGVirtualMachine')
END

IF NOT EXISTS (SELECT * FROM [dbo].[LogAnalyticsIngestControl] WHERE StorageContainerName = 'argdiskexports')
BEGIN
    INSERT INTO [dbo].[LogAnalyticsIngestControl] 
    VALUES ('argdiskexports', '1901-01-01T00:00:00Z', -1, 'DisksV1', 'ARGManagedDisk')
END

IF NOT EXISTS (SELECT * FROM [dbo].[LogAnalyticsIngestControl] WHERE StorageContainerName = 'argvhdexports')
BEGIN
    INSERT INTO [dbo].[LogAnalyticsIngestControl] 
    VALUES ('argvhdexports', '1901-01-01T00:00:00Z', -1, 'VhdDisksV1', 'ARGUnmanagedDisk')
END

IF NOT EXISTS (SELECT * FROM [dbo].[LogAnalyticsIngestControl] WHERE StorageContainerName = 'argavailsetexports')
BEGIN
    INSERT INTO [dbo].[LogAnalyticsIngestControl] 
    VALUES ('argavailsetexports', '1901-01-01T00:00:00Z', -1, 'AvailSetsV1', 'ARGAvailabilitySet')
END

IF NOT EXISTS (SELECT * FROM [dbo].[LogAnalyticsIngestControl] WHERE StorageContainerName = 'advisorexports')
BEGIN
    INSERT INTO [dbo].[LogAnalyticsIngestControl] 
    VALUES ('advisorexports', '1901-01-01T00:00:00Z', -1, 'AdvisorV1', 'AzureAdvisor')
END

IF NOT EXISTS (SELECT * FROM [dbo].[LogAnalyticsIngestControl] WHERE StorageContainerName = 'remediationlogs')
BEGIN
    INSERT INTO [dbo].[LogAnalyticsIngestControl] 
    VALUES ('remediationlogs', '1901-01-01T00:00:00Z', -1, 'RemediationV1', 'RemediationLogs')
END

IF NOT EXISTS (SELECT * FROM [dbo].[LogAnalyticsIngestControl] WHERE StorageContainerName = 'consumptionexports')
BEGIN
    INSERT INTO [dbo].[LogAnalyticsIngestControl] 
    VALUES ('consumptionexports', '1901-01-01T00:00:00Z', -1, 'ConsumptionV1', 'AzureConsumption')
END
