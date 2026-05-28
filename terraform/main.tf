terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# ----------------------------
# 1. Resource Group
# ----------------------------
resource "azurerm_resource_group" "rg" {
  name     = "rg-gitops-project"
  location = "East US"
}

# ----------------------------
# 2. Virtual Network
# ----------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "gitops-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ----------------------------
# 3. Azure Container Registry
# ----------------------------
resource "azurerm_container_registry" "acr" {
  name                = "acrigitopsprojectunique123" # must be globally unique
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  admin_enabled       = true
}

# ----------------------------
# 4. AKS Cluster
# ----------------------------
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-gitops-cluster"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "gitopscluster"

  default_node_pool {
    name           = "default"
    node_count     = 1
    vm_size        = "Standard_B2s_v2"
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  # IMPORTANT FIX: prevent CIDR overlap
  network_profile {
    network_plugin     = "azure"
    service_cidr       = "10.240.0.0/16"
    dns_service_ip     = "10.240.0.10"
    docker_bridge_cidr = "172.17.0.1/16"
  }
}

# ----------------------------
# 5. Allow AKS to Pull from ACR
# ----------------------------
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.acr.id
}