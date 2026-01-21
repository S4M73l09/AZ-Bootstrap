#!/bin/bash

# Este script crea los recursos de Azure necesarios para el backend de estado de Terraform.
# Se debe ejecutar una sola vez para la configuración inicial.
#
# INSTRUCCIONES:
# 1. Asegúrate de estar en el directorio `00-setup/`.
# 2. Dale permisos de ejecución al script: `chmod +x create_backend.sh`
# 3. Ejecútalo: `./create_backend.sh`

# --- CONFIGURACIÓN ---
# ¡IMPORTANTE! Cambia "WestEurope" a la región de Azure que prefieras.
# Puedes ver una lista con: az account list-locations --query "[].name" -o tsv
LOCATION="WestEurope"

# Nombre base para los recursos. Se añadirá un sufijo único para evitar conflictos.
RESOURCE_GROUP_NAME_BASE="rg-bootstrap-state"
STORAGE_ACCOUNT_NAME_BASE="stbootstraptfstate"
PUBLIC_NETWORK_ACCESS="Enabled" # Usa "Disabled" si tienes Private Endpoint configurado.

# --- LÓGICA DEL SCRIPT (No editar a menos que sepas lo que haces) ---

echo "🔄 Preparando la creación del backend de Terraform..."

# Genera un sufijo aleatorio de 5 caracteres para asegurar que los nombres sean únicos.
UNIQUE_SUFFIX=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 5)

RESOURCE_GROUP_NAME="$RESOURCE_GROUP_NAME_BASE-$UNIQUE_SUFFIX"
STORAGE_ACCOUNT_NAME="$STORAGE_ACCOUNT_NAME_BASE$UNIQUE_SUFFIX"
CONTAINER_NAME="tfboot"

echo "------------------------------------------------"
echo "Se crearán los siguientes recursos en Azure:"
echo "  🔹 Grupo de Recursos:      $RESOURCE_GROUP_NAME"
echo "  🔹 Cuenta de Almacenamiento: $STORAGE_ACCOUNT_NAME"
echo "  🔹 Contenedor:             $CONTAINER_NAME"
echo "  📍 Ubicación (Región):     $LOCATION"
echo "------------------------------------------------"
read -p "🤔 ¿Estás de acuerdo? (s/n): " CONFIRM
if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
    echo "❌ Operación cancelada por el usuario."
    exit 1
fi

# 1. Crear el Grupo de Recursos
echo -n "⏳ Creando Grupo de Recursos... "
az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" --output none
if [ $? -ne 0 ]; then
    echo "🔥 ¡Error! No se pudo crear el Grupo de Recursos."
    exit 1
fi
echo "✅ Hecho."

# 2. Crear la Cuenta de Almacenamiento
echo -n "⏳ Creando Cuenta de Almacenamiento (puede tardar un minuto)... "
az storage account create \
  --name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --location "$LOCATION" \
  --sku "Standard_LRS" \
  --https-only true \
  --min-tls-version TLS1_2 \
  --encryption-services "blob" \
  --allow-blob-public-access false \
  --output none
if [ $? -ne 0 ]; then
    echo "🔥 ¡Error! No se pudo crear la Cuenta de Almacenamiento."
    # Opcional: Limpieza en caso de fallo
    # az group delete --name $RESOURCE_GROUP_NAME --yes --no-wait
    exit 1
fi
echo "✅ Hecho."

# 3. Bloquear acceso publico si aplica
if [ "$PUBLIC_NETWORK_ACCESS" = "Disabled" ]; then
  echo -n "⏳ Deshabilitando acceso publico a la cuenta de almacenamiento... "
  az storage account update \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --public-network-access Disabled \
    --output none
  if [ $? -ne 0 ]; then
      echo "🔥 ¡Error! No se pudo deshabilitar el acceso publico."
      exit 1
  fi
  echo "✅ Hecho."
fi

# 4. Habilitar versionado y soft delete
echo -n "⏳ Configurando protección de blobs (versioning/soft delete)... "
az storage account blob-service-properties update \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --enable-versioning true \
  --delete-retention-days 14 \
  --container-delete-retention-days 14 \
  --output none
if [ $? -ne 0 ]; then
    echo "🔥 ¡Error! No se pudieron configurar las propiedades de blobs."
    exit 1
fi
echo "✅ Hecho."

# 5. Crear el Contenedor Blob (Azure AD auth)
echo -n "⏳ Creando Contenedor Blob... "
az storage container create \
  --name "$CONTAINER_NAME" \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --auth-mode login \
  --output none
if [ $? -ne 0 ]; then
    echo "🔥 ¡Error! No se pudo crear el Contenedor."
    echo "👉 Asegúrate de tener el rol 'Storage Blob Data Contributor' sobre la cuenta de almacenamiento."
    exit 1
fi
echo "✅ Hecho."


# --- FINALIZADO ---
echo ""
echo "🎉 ¡Éxito! El backend para el estado de Terraform ha sido creado."
echo ""
echo "Guarda estos nombres, los necesitaremos en el siguiente paso para configurar Terraform:"
echo "------------------------------------------------"
echo "resource_group_name  = \"$RESOURCE_GROUP_NAME\""
echo "storage_account_name = \"$STORAGE_ACCOUNT_NAME\""
echo "container_name       = \"$CONTAINER_NAME\""
echo "------------------------------------------------"
echo "Nota: para el backend con Azure AD (sin access keys), usa RBAC y OIDC."
