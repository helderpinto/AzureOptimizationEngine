SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
IF NOT EXISTS (SELECT * FROM sysobjects WHERE id = object_id(N'[dbo].[Recommendations]') AND OBJECTPROPERTY(id, N'IsUserTable') = 1)
	BEGIN
		CREATE TABLE [dbo].[Recommendations](
			[RecommendationId] [uniqueidentifier] NOT NULL DEFAULT NEWID(),
			[GeneratedDate] [datetime] NOT NULL,
			[Cloud] [varchar](20) NOT NULL,
			[Category] [varchar](50) NOT NULL,
			[ImpactedArea] [varchar](50) NOT NULL,
			[Impact] [varchar](20) NOT NULL,
			[RecommendationType] [varchar](50) NOT NULL,
			[RecommendationSubType] [varchar](50) NOT NULL,
			[RecommendationSubTypeId] [uniqueidentifier] NOT NULL,
			[RecommendationDescription] [nvarchar](1000) NULL,
			[RecommendationAction] [nvarchar](1000) NULL,
			[InstanceId] [varchar](1000) NULL,
			[InstanceName] [varchar](500) NULL,
			[AdditionalInfo] [nvarchar](max) NULL,
			[ResourceGroup] [varchar](200) NULL,
			[SubscriptionGuid] [varchar](50) NULL,
			[ConfidenceScore] [real] NOT NULL,
			[Tags] [nvarchar](max) NULL,
			[DetailsUrl] [nvarchar](max) NULL
		)

		ALTER TABLE [dbo].[Recommendations] ADD PRIMARY KEY CLUSTERED 
		(
			[RecommendationId] ASC
		)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ONLINE = OFF) ON [PRIMARY]
	END
ELSE
	BEGIN
		ALTER TABLE [dbo].[Recommendations] ALTER COLUMN [RecommendationAction] VARCHAR (1000) NULL
		ALTER TABLE [dbo].[Recommendations] ALTER COLUMN [InstanceId] VARCHAR (1000) NULL
		ALTER TABLE [dbo].[Recommendations] ALTER COLUMN [InstanceName] VARCHAR (500) NULL
		ALTER TABLE [dbo].[Recommendations] ALTER COLUMN [ResourceGroup] VARCHAR (200) NULL
		IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[Recommendations]') AND name = 'FitScore'
)		BEGIN
			EXEC sp_rename '[dbo].[Recommendations].ConfidenceScore', 'FitScore', 'COLUMN'
		END
	END