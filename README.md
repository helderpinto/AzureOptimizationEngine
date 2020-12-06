# Azure Optimization Engine

The Azure Optimization Engine (AOE) is an extensible solution designed to generate optimization recommendations for your Azure environment. See it like a fully customizable Azure Advisor. Actually, the first recommendations use-case covered by this tool was augmenting Azure Advisor Cost recommendations, particularly Virtual Machine right-sizing, with a fit score based on VM metrics and properties. Other recommendations can be easily added/augmented with this tool, not only for cost optimization but also for security, high availability and other [Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/) areas.

It is highly recommended that you read the whole blog series dedicated to this project, starting [here](https://techcommunity.microsoft.com/t5/core-infrastructure-and-security/augmenting-azure-advisor-cost-recommendations-for-automated/ba-p/1339298). You'll find all the information needed to correctly set up the whole environment.

## Deployment instructions

You must first install the Az Powershell module (instructions [here](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps)). Then, you can either choose to deploy all the dependencies from the GitHub repository or from your own. In any case, you must clone/download the solution locally, to be able to call the deployment script from a PowerShell **elevated prompt**.

During deployment, you'll be asked several questions. You must plan for the following:

* Whether you're going to reuse an existing Log Analytics Workspace or a create a new one
* Azure subscription to deploy the solution (if you're reusing a Log Analytics workspace, you must deploy into the same subscription the workspace is in).
* A unique name prefix for the Azure resources being created (if you have specific naming requirements, you can also choose resource names during deployment)
* Azure datacenter location
* Using a user account with Owner permissions over the chosen subscription and enough privileges to register Azure AD applications ([see details](https://docs.microsoft.com/en-us/azure/automation/manage-runas-account#permissions)).

If the deployment fails for some reason, you can simply repeat it, as it is idempotent. The same if you want to upgrade a previous deployment with the latest version of the repo. You just have to keep the same deployment options.

### Requirements

* Azure Powershell 4.5.0+

### Deploying from GitHub

```powershell
.\Deploy-AzureOptimizationEngine.ps1 [-AzureEnvironment <AzureChinaCloud|AzureUSGovernment|AzureGermanCloud|AzureCloud>]

# examples
.\Deploy-AzureOptimizationEngine.ps1

.\Deploy-AzureOptimizationEngine.ps1 -AzureEnvironment AzureChinaCloud
```

### Deploying from your own repo

You must publish the solution files into a publicly reachable URL. If you're using a Storage Account private container, you must also specify a SAS token.

```powershell
.\Deploy-AzureOptimizationEngine.ps1 -TemplateUri <URL to the ARM template JSON file (e.g., https://contoso.com/azuredeploy.json)> [-ArtifactsSasToken <Storage Account SAS token>] [-AzureEnvironment <AzureChinaCloud|AzureUSGovernment|AzureGermanCloud|AzureCloud>]

# examples
.\Deploy-AzureOptimizationEngine.ps1 -TemplateUri "https://contoso.com/azuredeploy.json"

.\Deploy-AzureOptimizationEngine.ps1 -TemplateUri "https://aoesa.blob.core.windows.net/files/azuredeploy.json" -ArtifactsSasToken "?sv=2019-10-10&ss=bfqt&srt=o&sp=rwdlacupx&se=2020-06-13T23:27:18Z&st=2020-06-13T15:27:18Z&spr=https&sig=4cvPayBlF67aYvifwu%2BIUw8Ldh5txpFGgXlhzvKF3%2BI%3D"
```

## Usage instructions

Once successfully deployed, and assuming you have your VMs onboarded to Log Analytics and collecting all the [required performance counters](https://techcommunity.microsoft.com/t5/core-infrastructure-and-security/augmenting-azure-advisor-cost-recommendations-for-automated/ba-p/1457687), we have everything that is needed to start augmenting Advisor recommendations and even generate custom ones!

This solution currently supports several types of recommendations, not restricted to Cost optimization:

* Advisor Cost recommendations augmented with a fit score based on Virtual Machine performance metrics (collected by Log Analytics agents) and Azure properties
* Delete unattached disks
* Upgrade Virtual Machines to Managed Disks

For Advisor Cost recommendations, the AOE's default configuration produces percentile 99th VM metrics aggregations, but you can adjust those to be less conservative. There are also adjustable metrics thresholds that are used to compute the fit score. The default thresholds values are 30% for CPU (5% for shutdown recommendations), 50% for memory (100% for shutdown) and 750 Mbps for network bandwidth (10 Mbps for shutdown). All the adjustable configurations are available as Azure Automation variables.

### Visualizing recommendations with Power BI

The AOE includes a [Power BI sample report](./views/GenericReport.pbix) for visualizing recommendations. To use it, you have first to change the data source connection to the SQL Database you deployed with the AOE. In the Power BI top menu, choose Transform Data > Data source settings.

![Open the Transform Data > Data source settings menu item](./docs/powerbi-transformdatamenu.jpg "Transform Data menu options")

Then click on "Change source" and change to your SQL database server URL (don't forget to ensure your SQL Firewall rules allow for the connection).

![Click on Change source and update SQL Server URL](./docs/powerbi-datasourcesettings.jpg "Update data source settings")

If the connection fails at the first try, this might be because the SQL Database was paused (it was deployed in the cheap Serverless plan). At the next try, the connection should open normally.

The report was built for a scenario where you have an "environment" tag applied to your resources. If you want to change this or add new tags, open the Transform Data menu again, but now choose the Transform data sub-option. A new window will open. If you click next in "Advanced editor" option, you can edit the data transformation logic and update the tag processing instructions.

![Open the Transform Data > Transform data menu item, click on Advanced editor and edit accordingly](./docs/powerbi-transformdata.jpg "Update data transformation logic")

### Adjusting Azure Automation Run As Account permissions

By default, the Azure Automation Run As Account is created with Contributor role over the respective subscription. The simplest minimum required permissions for the AOE runbooks are: 

* Reader role in every subscription you want to gather recommendations from.
* Contributor role in the resource group the solution was deployed to.