# Azure Optimization Engine

The Azure Optimization Engine is an extensible solution designed to generate optimization recommendations for your Azure environment. See it like a fully customizable Azure Advisor. Actually, the first recommendations use-case covered by this tool was augmenting Azure Advisor Cost recommendations, particularly Virtual Machine right-sizing, with a confidence score based on VM metrics and properties. Other recommendations can be easily added/augmented with this tool, not only for cost optimization but also for security, high availability and other areas.

It is highly recommended that you read the whole blog series dedicated to this project, starting [here](https://techcommunity.microsoft.com/t5/core-infrastructure-and-security/augmenting-azure-advisor-cost-recommendations-for-automated/ba-p/1339298). You'll find all the information needed to correctly set up the whole environment.

## Deployment instructions

You must first install the Az Powershell module (instructions [here](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps)). Then, you can either choose to deploy all the dependencies from the GitHub repository or from your own. In any case, you must clone/download the solution locally, to be able to call the deployment script from a PowerShell **elevated prompt**.

During deployment, you'll be asked several questions. You must plan for the following:

* If you're going to reuse an existing Log Analytics Workspace or a create a new one
* Azure subscription to deploy the solution (if you're reusing a Log Analytics workspace, you must deploy into the same subscription the workspace is in).
* A unique name prefix for the Azure resources being created
* Azure datacenter location
* Using a user account with Owner permissions over the chosen subscription and enough privileges to register Azure AD applications ([see details](https://docs.microsoft.com/en-us/azure/automation/manage-runas-account#permissions)).

### Deploying from GitHub

```powershell
.\Deploy-AzureOptimizationEngine.ps1
```

### Deploying from your own repo

You must publish the solution files into a publicly reachable URL. If you're using a Storage Account private container, you must also specify a SAS token.

```powershell
.\Deploy-AzureOptimizationEngine.ps1 -TemplateUri <URL to the ARM template JSON file - azuredeploy.json> [-ArtifactsSasToken <Storage Account SAS token>]
```

## Usage instructions

Once successfully deployed, and assuming you have your VMs onboarded to Log Analytics and collecting all the required performance counters, we have everything that is needed to start augmenting Advisor recommendations and even generate custom ones! More details soon!