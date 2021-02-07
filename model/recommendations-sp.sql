IF OBJECT_ID ( N'[dbo].[GetRecommendations]', 'P' ) IS NOT NULL   
    DROP PROCEDURE [dbo].[GetRecommendations];  
GO  

CREATE PROCEDURE dbo.GetRecommendations   
AS   
    SET NOCOUNT ON;  
    SELECT * FROM [dbo].[Recommendations] R
    WHERE GeneratedDate > GETDATE()-365 AND NOT EXISTS (
        SELECT * FROM [dbo].[Filters]
        WHERE FilterType IN ('Snooze', 'Dismiss') AND IsEnabled = 1 AND FilterEndDate > GETDATE() AND RecommendationSubTypeId = R.RecommendationSubTypeId AND InstanceId = R.InstanceId 
    )  
GO  