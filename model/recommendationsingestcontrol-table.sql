SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
IF NOT EXISTS (SELECT * FROM sysobjects WHERE id = object_id(N'[dbo].[RecommendationsIngestControl]')
AND OBJECTPROPERTY(id, N'IsUserTable') = 1)
BEGIN
	CREATE TABLE [dbo].[RecommendationsIngestControl](
		[StorageContainerName] [varchar](50) NOT NULL,
		[LastProcessedDateTime] [datetime] NULL,
		[LastProcessedLine] [int] NULL,
		[ModelVersion] [varchar](50) NOT NULL
	)

	ALTER TABLE [dbo].[RecommendationsIngestControl] ADD PRIMARY KEY CLUSTERED 
	(
		[StorageContainerName] ASC
	)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ONLINE = OFF) ON [PRIMARY]
END