# Diccionario de Datos — Estado de Resultados (Shiny + MVP_Etapa2)

**Proyecto:** FINANZAS EN R — Estado de Resultados por PC (Real 26 vs Budget 26)  
**Autora:** Benazir María Castillo Rivas  
**Última actualización:**  
**Fuente principal:** `BBDD Estado Resultado Operacional.xlsx` (misma carpeta que `app.R` y `MVP_Etapa2.R`)

---

## 1) Propósito y alcance

Este diccionario describe todas las **variables utilizadas y generadas** por la solución completa:

### Incluye:
- **App Shiny (`app.R`)**  
  Visualización de **Venta**, **GOP**, **GOP%** por PC, comparando **Real_26 vs Budget_26**, bajo el calendario fiscal **Sep–Ago**.

- **MVP_Etapa2 (`MVP_Etapa2.R`)**  
  Generación del archivo Excel `MVP_Etapa2_Informe.xlsx` con:
  - Resumen YTD por PC + clasificación **LMC / Low Performance / Profitable**.  
  - Desviaciones por agrupador vs **Budget_26** y vs **Real_25**.  
  - GOP mensual.  
  - Hoja guía con definiciones.

> **Datos reales disponibles:** hasta diciembre 2025.  
> **Períodos considerados:** `Budget_26`, `Real_26`, `Real_25`.

---

## 2) Origen y estructura de datos

- **Archivo**: `BBDD Estado Resultado Operacional.xlsx`  
- **Encabezados**: limpiados con `janitor::clean_names()`  
- **Meses fiscales normalizados**: `sep` a `ago`  
- **Calendario fiscal**:  
  `sep=1`, `oct=2`, `nov=3`, `dic=4`, `ene=5`, `feb=6`, `mar=7`, `abr=8`, `may=9`, `jun=10`, `jul=11`, `ago=12`

### Columnas esperadas (se autodetectan por candidatos):
- `periodo`  
- `pc` / `profit_center` / `centro_costo`  
- `agrupador` / `hfm_account*` / `cuenta*`  
- `descripcion`  
- `cliente` / `denominacion_contrato`  
- `servicio`  
- `n_2`, `n_3`  
- meses `sep..ago`  
- `ytd`

---

## 3) Variables derivadas (App + MVP)

| Variable | Tipo | Descripción |
|---------|------|-------------|
| `periodo_src` | chr | Versión normalizada del período original |
| `periodo` | chr | `"Budget_26"`, `"Real_26"`, `"Real_25"` |
| `mes_txt` | chr | Mes en texto (`"sep"`..`"ago"`) |
| `mes_num` | int | Mes fiscal (1–12) |
| `mes_nombre` | chr | Nombre del mes en español |
| `monto` | num | Valor mensual transformado |
| `pc` | chr | Profit Center |
| `descripcion` | chr | Descripción del PC |
| `cli` | chr | Cliente |
| `srv` | chr | Servicio |
| `n2`, `n3` | chr | Jerarquías |
| `agrupador_val` | chr | Texto bruto del agrupador |
| `agrupador_std` | chr | Agrupador estandarizado (01–09, u “OTROS”) |

---

## 4) Conjuntos derivados — App Shiny

### 4.1. `venta_pc`
- Suma de revenue (`01_Revenue`)
- Agrupado por:  
  `pc, descripcion, n2, n3, mes_num, mes_nombre, periodo`

### 4.2. `gop_pc`
- Suma de GOP (`09_GOP`)
- Mismos atributos clave que venta

### 4.3. `gop_pc_full`
- Unión de venta y GOP  
- Columnas:  
  - claves  
  - `venta`  
  - `gop`  
  - `gop_pct = gop / venta` (o NA si venta=0)

---

## 5) Conjuntos derivados — MVP_Etapa2

### 5.1. `data_map`
Base en ancho que incluye:
- `ytd_val`  
- `periodo`  
- `agrupador_std`  
- `pc`

### 5.2. YTD Real_26
- `venta_ytd_real26`: suma de YTD Revenue  
- `gop_ytd_real26`: suma de YTD GOP

### 5.3. `resumen` (Resumen_GOP_PC)
Variables:
- `pc`, `descripcion`, `srv`, `n2`, `n3`  
- `venta_real26`  
- `gop_real26`  
- `gop_pct_real26`  
- `categoria`:
  - `< 0` → LMC  
  - `0–0.0799` → Low Performance  
  - `>= 0.08` → Profitable

### 5.4. `desv_agru` (Desv_Agrupador)
Incluye:
- `valor_real26`  
- `valor_budget26`  
- `valor_real25`  
- `desv_pct_r26_vs_b26`  
- `desv_pct_r26_vs_r25`

### 5.5. `gop_mensual` (GOP_Mensual)
- Orden por PC, mes y periodo  
- Columnas: `venta`, `gop`, `gop_pct`

---

## 6) Salidas

Carpeta generada:  
-Outputs

Archivo principal:
-MVP_Etapa2_Informe.xlsx
Hojas incluidas:
1. **Resumen_GOP_PC**  
2. **Desv_Agrupador**  
3. **GOP_Mensual**  
4. **Guia**

---

## 7) Tipos de dato

- **Texto:** `pc`, `descripcion`, `cli`, `srv`, `n2`, `n3`, `agrupador_val`, `agrupador_std`  
- **Numérico:** `monto`, `venta`, `gop`, `ytd_val`, `valor_*`, `gop_pct`, `desv_pct_*`  
- **Categorías:** `periodo`, `mes_nombre` (opcionales como factor)

---

## 8) Reglas de negocio

- Solo se incluyen: `Budget_26`, `Real_26`, `Real_25`  
- Calendario fiscal **Sep–Ago**  
- Estandarización de agrupadores por regex  
- Manejo seguro de divisiones (`NA` si venta=0)  
- Clasificación YTD basada en GOP%

---

## 9) Ejemplo ilustrativo

### Encabezados esperados:
periodo, pc, agrupador, descripcion, cliente, servicio, n_2, n_3,
sep, oct, nov, dic, ene, feb, mar, abr, may, jun, jul, ago, ytd
## 10) Contacto

- **Autora:** Benazir Castillo  
- **Profesor:** Sebastián Egaña  