@description('Name of the connector namespace (connector gateway) that hosts the GitHub connection and MCP server.')
param connectorGatewayName string

@description('Name of the GitHub connection created under the connector gateway.')
param connectionName string = 'github'

@description('Name of the MCP server configuration that exposes the GitHub connector as an MCP server.')
param mcpServerConfigName string = 'github-repo-activity'

param location string = resourceGroup().location
param tags object = {}

@description('Principal ID of the function app user-assigned managed identity, granted access to the GitHub connection.')
param managedIdentityPrincipalId string

@description('Principal ID of the deploying user, granted access so the connection can be authorized after deployment.')
param deployerPrincipalId string

param tenantId string

// Azure Connector Namespace (preview) — a managed integration resource that hosts
// prebuilt connectors and publishes them as MCP servers for AI agents to call as tools.
resource connectorGateway 'Microsoft.Web/connectorGateways@2026-05-01-preview' = {
  name: connectorGatewayName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

// GitHub connection. After deployment this connection must be authorized once via the
// Azure portal (OAuth consent to GitHub) before the MCP server can call GitHub on your behalf.
resource githubConnection 'Microsoft.Web/connectorGateways/connections@2026-05-01-preview' = {
  parent: connectorGateway
  name: connectionName
  properties: {
    connectorName: 'github'
    displayName: 'GitHub Connection'
  }
}

// Allow the function app's managed identity to use the connection at runtime.
resource githubConnectionAccessPolicy 'Microsoft.Web/connectorGateways/connections/accessPolicies@2026-05-01-preview' = {
  parent: githubConnection
  name: managedIdentityPrincipalId
  properties: {
    principal: {
      type: 'ActiveDirectory'
      identity: {
        objectId: managedIdentityPrincipalId
        tenantId: tenantId
      }
    }
  }
}

// Allow the deployer to manage/authorize the connection after deployment.
resource githubConnectionDeployerAccessPolicy 'Microsoft.Web/connectorGateways/connections/accessPolicies@2026-05-01-preview' = {
  parent: githubConnection
  name: deployerPrincipalId
  properties: {
    principal: {
      type: 'ActiveDirectory'
      identity: {
        objectId: deployerPrincipalId
        tenantId: tenantId
      }
    }
  }
}

// Publish the GitHub connector as an MCP server exposing concrete repository-activity
// operations as MCP tools (issues and pull requests). The connector namespace does not
// expose a GitHub Actions workflow-runs operation, so the digest covers PRs and issues.
resource githubMcpServerConfig 'Microsoft.Web/connectorGateways/mcpserverconfigs@2026-05-01-preview' = {
  parent: connectorGateway
  name: mcpServerConfigName
  properties: {
    state: 'Enabled'
    description: 'GitHub repository activity (issues and pull requests) exposed as an MCP server.'
    connectors: [
      {
        name: 'github'
        connectionName: githubConnection.name
        displayName: 'GitHub'
        description: 'Read GitHub repository activity for digests.'
        operations: [
          {
            name: 'GetPullRequests'
            displayName: 'List pull requests'
            description: 'Get pull requests for a repository. Use state=open for open PRs, state=closed for merged/closed PRs.'
            userParameters: []
            agentParameters: [
              {
                name: 'repositoryOwner'
                schema: {
                  type: 'string'
                  description: 'Repository owner (org or user), e.g. Azure'
                  required: true
                }
              }
              {
                name: 'repositoryName'
                schema: {
                  type: 'string'
                  description: 'Repository name, e.g. azure-functions-host'
                  required: true
                }
              }
              {
                name: 'state'
                schema: {
                  type: 'string'
                  description: 'Filter by state: open, closed, or all'
                }
              }
              {
                name: 'sort'
                schema: {
                  type: 'string'
                  description: 'Sort by: created, updated, or popularity'
                }
              }
              {
                name: 'direction'
                schema: {
                  type: 'string'
                  description: 'Sort direction: asc or desc'
                }
              }
              {
                name: 'per_page'
                schema: {
                  type: 'integer'
                  description: 'Results per page (max 100)'
                }
              }
            ]
          }
          {
            name: 'GetIssues'
            displayName: 'List issues'
            description: 'Get issues for a repository. Use state and since to filter; results may include pull requests.'
            userParameters: []
            agentParameters: [
              {
                name: 'repositoryOwner'
                schema: {
                  type: 'string'
                  description: 'Repository owner (org or user), e.g. Azure'
                  required: true
                }
              }
              {
                name: 'repositoryName'
                schema: {
                  type: 'string'
                  description: 'Repository name, e.g. azure-functions-host'
                  required: true
                }
              }
              {
                name: 'state'
                schema: {
                  type: 'string'
                  description: 'Filter by state: open, closed, or all'
                }
              }
              {
                name: 'since'
                schema: {
                  type: 'string'
                  description: 'ISO 8601 timestamp; only issues updated at or after this time'
                }
              }
              {
                name: 'sort'
                schema: {
                  type: 'string'
                  description: 'Sort by: created, updated, or comments'
                }
              }
              {
                name: 'direction'
                schema: {
                  type: 'string'
                  description: 'Sort direction: asc or desc'
                }
              }
              {
                name: 'per_page'
                schema: {
                  type: 'integer'
                  description: 'Results per page (max 100)'
                }
              }
            ]
          }
          {
            name: 'SearchGithubWithQuery'
            displayName: 'Search GitHub'
            description: 'Search GitHub using a query string (GitHub search syntax).'
            userParameters: []
            agentParameters: [
              {
                name: 'query'
                schema: {
                  type: 'string'
                  description: 'GitHub search query, e.g. repo:Azure/azure-functions-host is:pr is:merged'
                  required: true
                }
              }
            ]
          }
        ]
      }
    ]
    policies: []
    settings: {}
  }
}

output connectorGatewayName string = connectorGateway.name
output connectionId string = githubConnection.id
output connectionName string = githubConnection.name
output mcpEndpointUrl string = githubMcpServerConfig.properties.mcpEndpointUrl
