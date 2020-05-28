IF NOT EXISTS (SELECT * FROM [dbo].[RecommendationsIngestControl] WHERE StorageContainerName = 'recommendationsexports')
BEGIN
    INSERT INTO [dbo].[RecommendationsIngestControl] 
    VALUES 
        ('recommendationsexports', '1901-01-01T00:00:00Z', -1, 'AOEGenericv1')
END