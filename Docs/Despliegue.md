# Despliegue — Proyecto Finanzas en R (Shiny App)

## 1. Objetivo del despliegue
Poner en operación la aplicación Shiny que calcula y visualiza Venta y GOP (Real vs Budget) a partir del archivo Excel fuente.

## 2. Ambiente de despliegue (actual)
- Computador personal Mac con RStudio.
- Proyecto organizado en una carpeta única:
  - `app.R` (aplicación Shiny)
  - `BBDD Estado Resultado Operacional.xlsx` (fuente)
  - `Outputs/` (informes generados)
  - `docs/` (documentación)

## 3. Método de despliegue utilizado
Actualmente el despliegue es **local**, usando RStudio.

### Pasos:
1. Abrir el proyecto `.Rproj`.
2. Abrir `app.R`.
3. Ejecutar:
   - Botón **Run App** en la esquina superior derecha.
   - O en consola: `shiny::runApp()`.
4. La app se abre en el navegador en modo producción local.

### Características del despliegue local:
- No requiere servidor.
- Mantiene el Excel fuente en la misma carpeta del proyecto.
- Es reproducible en cualquier Mac o PC con R y RStudio.

## 4. Despliegue recomendado a futuro
### Opción A — **Posit Connect** (empresa)
Publicar directamente desde RStudio:
- Botón: **Publish** → “Shiny Application”.
- Permite permisos, URL fija, logs, escalamiento.

### Opción B — **Docker + Shiny Server** (independiente)
- Crear una imagen que contenga R + app.
- Correrla en cualquier servidor.

## 5. Requisitos del entorno
- R 4.x
- RStudio
- Paquetes: shiny, dplyr, readxl, tidyr, etc.
- Excel fuente ubicado junto al archivo `app.R`

## 6. Validación post-despliegue
- Se probaron filtros (N+3, N+2, Descripción/PC, Mes).
- Se validaron los gráficos de:
  - Venta vs GOP (Real vs Budget).
  - Tendencia GOP%.
- Se probó la pestaña Auditoría.