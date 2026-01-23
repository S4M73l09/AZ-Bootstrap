# Azure Bootstrap con Terraform

Este proyecto configura la infraestructura base en Azure utilizando Terraform. Está diseñado para establecer una base sólida y gobernable para futuras cargas de trabajo, almacenando el estado de Terraform de forma remota y segura.

## Prerrequisitos

-   [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
-   [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## Pasos de Configuración Inicial

### 1. Iniciar sesión en Azure

Primero, autentícate en tu cuenta de Azure y selecciona la suscripción donde deseas desplegar los recursos.

```bash
# Inicia sesión de forma interactiva
az login

# Establece la suscripción a utilizar
az account set --subscription "<NOMBRE_O_ID_DE_TU_SUSCRIPCION>"
```

### 2. Creación del Backend para Terraform

Para colaborar y mantener la seguridad, el estado de Terraform se guarda en una cuenta de Azure Storage. Hemos automatizado su creación.

1.  **Ejecutar el script**: El script `create_backend.sh` se encarga de crear un grupo de recursos, una cuenta de almacenamiento y un contenedor (`tfboot`) para guardar el fichero `terraform.tfstate`.
    ```bash
    bash 00-setup/create_backend.sh
    ```
2.  **Salida del script**: Al finalizar, el script te proporcionará los nombres de los recursos creados. Estos datos son cruciales para configurar el backend en Terraform.
3.  **Acceso publico**: Si `PUBLIC_NETWORK_ACCESS=Disabled`, el script deshabilita el acceso publico del Storage Account.

### 3. Configuración de Terraform

Con los recursos del backend ya creados, configuramos Terraform para que los utilice.

1.  **Archivo `backend.tf`**: En el directorio `10-governance/`, hemos creado un archivo `backend.tf` para decirle a Terraform dónde debe guardar su estado usando Azure AD (sin access keys). La configuración es la siguiente:
    ```terraform
    terraform {
      backend "azurerm" {
        resource_group_name  = "rg-bootstrap-state-aq7yx"
        storage_account_name = "stbootstraptfstateaq7yx"
        container_name       = "tfboot"
        key                  = "10-governance.tfstate"
        use_azuread_auth     = true
      }
    }
    ```
2.  **Archivo `main.tf`**: En el mismo directorio, un fichero `main.tf` define el proveedor que usará Terraform, en este caso, `azurerm` (Azure).
    ```terraform
    terraform {
      required_version = "= 1.14.3"
      required_providers {
        azurerm = {
          source  = "hashicorp/azurerm"
          version = "= 3.117.1"
        }
      }
    }
    ```
3.  **Inicialización**: El último paso es ejecutar `terraform init` dentro de la carpeta `10-governance/`. Este comando prepara el entorno, descarga el proveedor de Azure y conecta Terraform con el backend remoto que hemos configurado.

## State por carpeta

Cada etapa tiene su propio state en la misma Storage Account y contenedor, con `key` distinta:

- `10-governance/` -> `10-governance.tfstate`
- `20-logging/` -> `20-logging.tfstate`
- `30-networking/` -> `30-networking.tfstate`
- `40-shared-services/` -> `40-shared-services.tfstate`

## Gobernanza (10-governance)

Se aplican policies al RG `rg-bootstrap-state-aq7yx`:

- Tags obligatorios: `owner`, `env`, `costCenter`
- Regiones permitidas (ej. `westeurope`)
- Bloqueo de Public IP

## Logging y alertas (20-logging)

Se crea un RG dedicado `rg-bootstraplogging-state-aq7yx` con un Log Analytics Workspace:

- Retención: 30 días
- Diagnósticos: Activity Log de la suscripción
- Diagnósticos: Storage Account del state (`stbootstraptfstateaq7yx`)
- Export: Archive en Storage Account (`stbootlogarchaq7yx`)
- Alertas: eliminación de RG y de Storage Account
- Action Group: email definido en `alert_email`
- Dashboard: portal dashboard básico con referencia al workspace
- Nota: se ignoran cambios en `metric` del diagnostic setting para evitar drift de Azure (ver `ignore_changes`).

## Networking (30-networking)

Se crea red dedicada para Private Endpoints:

- RG: `network-Bootstrap`
- VNet: `10.10.0.0/16`
- Subnet Private Endpoints: `10.10.1.0/24`
- Private DNS Zone: `privatelink.blob.core.windows.net`
- Private Endpoints para:
  - Storage Account del state
  - Storage Account de archive

Nota: para bloquear acceso publico, usar `public_network_access_enabled = false` en la Storage Account de archive y deshabilitar acceso publico en la Storage Account del state (si ya existe, hacerlo via `az storage account update`).

## Shared services (40-shared-services)

VM minima para self-hosted runner (Linux):

- RG: `rg-bootstrap-shared`
- VM: `vm-bootstrap-runner` (B1s)
- Subnet: `10.10.2.0/24`
- SSH: clave publica en `ssh_public_key`
- NSG: permite SSH desde `ssh_allowed_cidrs` (ajusta en produccion)

## Runner self-hosted (GitHub Actions)

Pasos resumidos:

1. Crear la VM con `40-shared-services/`.
2. Instalar dependencias en la VM:
   ```bash
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
   wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
   echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
   sudo apt-get update && sudo apt-get install -y terraform
   ```
3. Registrar runner:
   - GitHub → Settings → Actions → Runners → New self-hosted runner (Linux)
   - Ejecutar los comandos en la VM
   - Instalar y arrancar el servicio:
     ```bash
     sudo ./svc.sh install
     sudo ./svc.sh start
     ```
4. Asegurar etiqueta `azure` si usamos `runs-on: [self-hosted, azure]` para mayor seguridad y monitorizacion.

Nota: los workflows incluyen jobs para **encender/apagar** la VM (`start_runner` / `stop_runner`). Ademas de incluir jobs checks `Setup Terraform` para que vea si en el runner esta instalado Terraform, si el check indica que no esta Terraform instalado, dicho paso se activa para que se instale.

## Siguientes Pasos: Automatización con GitHub Actions (OIDC)

El siguiente paso es automatizar los despliegues con GitHub Actions usando **OIDC** (sin secrets). El flujo general es:

1.  **Registrar una App en Azure Entra ID**: Se crea una identidad para GitHub Actions.
2.  **Configurar Federated Credentials**: Se liga el repo y la rama (`refs/heads/main`).
3.  **Asignar RBAC**: Dar permisos mínimos sobre la suscripción o grupo de recursos.
4.  **Crear Workflows**: Se definen los pasos de `plan` y `apply` en `.github/workflows/` para `10-governance/`, `20-logging/`, `30-networking/` y `40-shared-services/`, con aprobación manual vía `environment`.

Con esto, el proceso de CI/CD para la infraestructura queda establecido sin manejar claves.

## Drift detection (GitHub Actions)

Workflow separado en `.github/workflows/drift.yml`:

- Corre diario (cron) y manual (`workflow_dispatch`)
- El job de `Setup Terraform` se ejecuta solo si el check verifica que no esta Terraform instalado en el runner.
- Ejecuta `terraform plan -detailed-exitcode` en `10-governance/`, `20-logging/`, `30-networking/` y `40-shared-services/`
- Publica resumen en Job Summary (incluye extracto del plan si hay drift)
- Sube artifacts: `tfplan`, `plan.txt`, `plan.show.txt`
- Envía email con Gmail usando:
  - `vars.GMAIL_ALERT` (email destino)
  - `secrets.AZ_BOOTSTRAP_GMAIL_ALERT` (app password)

## State check (GitHub Actions)

Workflow manual para verificar acceso al backend:

- Archivo: `.github/workflows/state-check.yml`
- Usa el runner `self-hosted, azure`
- Autenticación OIDC y `terraform init` en `10-governance/`
- Incluye `start_runner` y `stop_runner` para encender/apagar la VM

## Estado privado del backend

Para mantener el state privado:

1. Asegura los tags requeridos en el Storage Account del state (`owner`, `env`, `costCenter`).
2. Deshabilita el acceso público:
   ```bash
   az storage account update \
     --name stbootstraptfstateaq7yx \
     --resource-group rg-bootstrap-state-aq7yx \
     --public-network-access Disabled
   ```
3. Verifica el estado:
   ```bash
   az storage account show \
     --name stbootstraptfstateaq7yx \
     --resource-group rg-bootstrap-state-aq7yx \
     --query publicNetworkAccess -o tsv
   ```
4. Ejecuta el workflow `state-check` para confirmar acceso desde el runner privado.

## RBAC minimo para OIDC

Rol custom para la app OIDC en la suscripcion (permite crear/editar/eliminar recursos del bootstrap):

Archivo: `50-custom-roles/role-bootstrap-custom.json`

Crear rol:

```bash
az role definition create --role-definition 50-custom-roles/role-bootstrap-custom.json
```

Actualizar rol (si cambian permisos):

```bash
az role definition update --role-definition 50-custom-roles/role-bootstrap-custom.json
```

Asignar rol a la app OIDC:

```bash
az role assignment create \
  --assignee f8053b2b-0618-4baf-9764-dd6edd5ca136 \
  --role "BootstrapCustomOperator" \
  --scope /subscriptions/2a23dc3f-267e-4cd1-a12a-695e2623f1f7
```

Nota: el backend del state requiere ademas `Storage Blob Data Contributor` en la Storage Account del state.

## Rotacion OIDC

Pasos recomendados para rotar la app OIDC:

1. Crear una nueva App en Entra ID.
2. Asignar el rol custom `BootstrapCustomOperator` y el rol `Storage Blob Data Contributor` (state).
3. Crear el Federated Credential (repo + rama).
4. Actualizar `AZ_APPID_BOOTSTRAP` en GitHub Variables.
5. Ejecutar un workflow de prueba (plan) para validar acceso.

Si solo cambia la rama o environment, basta con actualizar el Federated Credential.
Cuando la nueva app funcione, eliminar la app antigua y sus role assignments.

## Operación diaria

Comandos básicos por carpeta:

```bash
cd 10-governance
terraform init
terraform plan
terraform apply
```

```bash
cd 20-logging
terraform init
terraform plan
terraform apply
```

```bash
cd 30-networking
terraform init
terraform plan
terraform apply
```

```bash
cd 40-shared-services
terraform init
terraform plan
terraform apply
```

Dónde revisar resultados:

- GitHub Actions: Job Summary y artifacts en el workflow de drift.
- Para aplicar cambios manuales, usa el workflow principal con `environment` de aprobación.

## Orden de despliegue

Orden recomendado (por dependencias entre stages):

1. `10-governance/`
2. `20-logging/`
3. `30-networking/` (requiere el Storage Account de archive)
4. `40-shared-services/` (requiere la VNet)

El workflow aplica este orden y omite `30-networking/` si el archive no existe.

## Troubleshooting

Errores comunes y soluciones:

- **403 al iniciar backend (AzureAD auth)**:  
  Error típico: `AuthorizationPermissionMismatch` al listar blobs.  
  Solución: asignar rol **Storage Blob Data Contributor** a la identidad que ejecuta Terraform (tu usuario local y/o la app OIDC) en el scope de la Storage Account del state.

- **`azurerm_policy_assignment` no soportado**:  
  Solución: usar `azurerm_resource_group_policy_assignment` para scope de RG.

- **Retención de Log Analytics fuera de rango**:  
  `retention_in_days` mínimo **30** para `PerGB2018`.

- **Nombre de Storage Account inválido**:  
  Debe ser minúsculas/números y 3–24 caracteres.

- **Argumento inválido `allow_blob_public_access`**:  
  Solución: usar `allow_nested_items_to_be_public = false` en `azurerm_storage_account`.

Si aparece un error nuevo, añádelo aquí con su solución para mantener la guía actualizada.

## Estructura del Proyecto

-   `00-setup/`: Contiene scripts para la configuración inicial.
-   `10-governance/`: Contiene la configuración raíz de Terraform para el gobierno de la suscripción.
-   `20-logging/`: Configuración de logging y diagnósticos.
-   `30-networking/`: Destinado a los recursos de red centrales.
-   `40-shared-services/`: VM para self-hosted runner.
-   `50-custom-roles/`: Destinado a roles personalizados
