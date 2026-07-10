targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment used to generate a short unique hash for resource names.')
param environmentName string

@minLength(1)
@description('Primary location for all resources. Must support Azure Functions Flex Consumption, Microsoft.Web connectorGateways, and the Microsoft Foundry gpt-5-mini Global Standard deployment.')
@allowed([
  'centralus'
  'eastus'
  'eastus2'
  'northcentralus'
  'southcentralus'
  'westus'
])
@metadata({
  azd: {
    type: 'location'
  }
})
param location string

@description('GitHub repository (owner/name) the digest agent summarizes by default.')
param githubRepository string = 'Azure/azure-functions-host'

@description('Microsoft Foundry model deployment name.')
param foundryModel string = 'gpt-5-mini'

@description('Microsoft Foundry model name.')
param foundryModelName string = 'gpt-5-mini'

@description('Microsoft Foundry model version.')
param foundryModelVersion string = '2025-08-07'

@description('Microsoft Foundry deployment capacity (thousands of tokens per minute).')
param foundryDeploymentCapacity int = 50

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var functionAppName = '${abbrs.webSitesFunctions}agents-${resourceToken}'
var foundryAccountName = 'cog-${resourceToken}'
var foundryProjectName = '${foundryAccountName}-proj'
var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(toLower(uniqueString(functionAppName, resourceToken)), 7)}'
var deployerPrincipalId = deployer().objectId
var connectorGatewayName = 'cg-${resourceToken}'
var githubConnectionName = 'github'
var githubMcpServerConfigName = 'github-repo-activity'

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module apiUserAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'apiUserAssignedIdentity'
  scope: rg
  params: {
    location: location
    tags: tags
    name: '${abbrs.managedIdentityUserAssignedIdentities}agents-${resourceToken}'
  }
}

module foundry './app/foundry.bicep' = {
  name: 'foundry'
  scope: rg
  params: {
    accountName: foundryAccountName
    projectName: foundryProjectName
    location: location
    tags: tags
    modelDeploymentName: foundryModel
    modelName: foundryModelName
    modelVersion: foundryModelVersion
    deploymentCapacity: foundryDeploymentCapacity
    managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
    deployerPrincipalId: deployerPrincipalId
  }
}

// GitHub connection published as an MCP server via an Azure Connector Namespace (preview)
module githubConnector './app/connector-gateway.bicep' = {
  name: 'githubConnector'
  scope: rg
  params: {
    connectorGatewayName: connectorGatewayName
    connectionName: githubConnectionName
    mcpServerConfigName: githubMcpServerConfigName
    location: location
    tags: tags
    managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
    deployerPrincipalId: deployerPrincipalId
    tenantId: tenant().tenantId
  }
}

module appServicePlan 'br/public:avm/res/web/serverfarm:0.1.1' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: '${abbrs.webServerFarms}${resourceToken}'
    sku: {
      name: 'FC1'
      tier: 'FlexConsumption'
    }
    reserved: true
    location: location
    tags: tags
  }
}

module api './app/api.bicep' = {
  name: 'api'
  scope: rg
  params: {
    name: functionAppName
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.name
    appServicePlanId: appServicePlan.outputs.resourceId
    runtimeName: 'python'
    runtimeVersion: '3.13'
    storageAccountName: storage.outputs.name
    deploymentStorageContainerName: deploymentStorageContainerName
    identityId: apiUserAssignedIdentity.outputs.resourceId
    identityClientId: apiUserAssignedIdentity.outputs.clientId
    appSettings: {
      AZURE_FUNCTIONS_AGENTS_PROVIDER: 'foundry'
      FOUNDRY_PROJECT_ENDPOINT: foundry.outputs.projectEndpoint
      FOUNDRY_MODEL: foundry.outputs.modelDeploymentName
      AZURE_CLIENT_ID: apiUserAssignedIdentity.outputs.clientId
      GITHUB_REPOSITORY: githubRepository
      GITHUB_MCP_SERVER_URL: githubConnector.outputs.mcpEndpointUrl
      GITHUB_MCP_CLIENT_ID: apiUserAssignedIdentity.outputs.clientId
      ENABLE_MULTIPLATFORM_BUILD: 'true'
    }
  }
}

module storage 'br/public:avm/res/storage/storage-account:0.8.3' = {
  name: 'storage'
  scope: rg
  params: {
    name: '${abbrs.storageStorageAccounts}${resourceToken}'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    dnsEndpointType: 'Standard'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    blobServices: {
      containers: [{ name: deploymentStorageContainerName }]
    }
    minimumTlsVersion: 'TLS1_2'
    location: location
    tags: tags
  }
}

module rbac './app/rbac.bicep' = {
  name: 'rbacAssignments'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    appInsightsName: monitoring.outputs.name
    managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
    deployerPrincipalId: deployerPrincipalId
  }
}

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.7.0' = {
  name: '${uniqueString(deployment().name, location)}-loganalytics'
  scope: rg
  params: {
    name: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
    dataRetention: 30
  }
}

module monitoring 'br/public:avm/res/insights/component:0.4.1' = {
  name: '${uniqueString(deployment().name, location)}-appinsights'
  scope: rg
  params: {
    name: '${abbrs.insightsComponents}${resourceToken}'
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.outputs.resourceId
    disableLocalAuth: true
  }
}

output AZURE_LOCATION string = location
output AZURE_FUNCTION_NAME string = api.outputs.SERVICE_API_NAME
output FOUNDRY_PROJECT_ENDPOINT string = foundry.outputs.projectEndpoint
output FOUNDRY_MODEL string = foundry.outputs.modelDeploymentName
output GITHUB_REPOSITORY string = githubRepository
output GITHUB_CONNECTOR_GATEWAY_NAME string = githubConnector.outputs.connectorGatewayName
output GITHUB_MCP_SERVER_URL string = githubConnector.outputs.mcpEndpointUrl
