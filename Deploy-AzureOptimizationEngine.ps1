#New-AzResourceGroupDeployment -TemplateUri https://hppfedevopssa.blob.core.windows.net/azureoptimizationengine/azuredeploy.json -ResourceGroupName azure-optimization-engine-rg -Name automation1

New-AzResourceGroupDeployment -TemplateUri $templateUri -ResourceGroupName $resourceGroupName -Name $deploymentName