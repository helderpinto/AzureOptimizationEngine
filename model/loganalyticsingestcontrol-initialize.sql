IF NOT EXISTS (SELECT * FROM [dbo].[LogAnalyticsIngestControl] WHERE StorageContainerName = 'argvmexports')
BEGIN
    INSERT INTO [dbo].[LogAnalyticsIngestControl] 
    VALUES ('argvmexports', '1901-01-01T00:00:00Z', -1, 'VMsV1')
END

IF NOT EXISTS (SELECT * FROM [dbo].[LogAnalyticsIngestControl] WHERE StorageContainerName = 'argdiskexports')
BEGIN
    INSERT INTO [dbo].[LogAnalyticsIngestControl] 
    VALUES ('argdiskexports', '1901-01-01T00:00:00Z', -1, 'DisksV1')
END

IF NOT EXISTS (SELECT * FROM [dbo].[LogAnalyticsIngestControl] WHERE StorageContainerName = 'advisorexports')
BEGIN
    INSERT INTO [dbo].[LogAnalyticsIngestControl] 
    VALUES ('advisorexports', '1901-01-01T00:00:00Z', -1, 'AdvisorV1')
END
