# ================================================

#FEN UCHILE
#ETAPA 2 PROYECTO EN CURSO 
# Informe de estado de resultados a partir de dos archivos Excel que contienen la información mensual de presupuestos,
# resultados del año anterior y resultados reales del año fiscal actual.
# MVP Etapa 2 - Estado de Resultados por PC (Periodo, Venta y GOP, Acumulado anual Year to Day YTD )
# Destacando LMC,LP Profitable y Desviaciones vs Presupuestos.
# Autor: Benazir Maria Castillo Rivas
# Profesor: Sebastian Egaña
# ===============================================

#Consideraciones de la Data: Información actualizada a Diciembre 2025, por ende no existe data Real para Enero 26 en adelante.

# ---- Instalación de Paquetes ----
pkgs <- c("readxl","dplyr","tidyr","stringr","janitor","lubridate","openxlsx","scales","rlang")
to_install <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(to_install)) install.packages(to_install, repos = "https://cloud.r-project.org")
invisible(lapply(pkgs, library, character.only = TRUE))

# ---- Helpers ----
msg  <- function(...) cat("[INFO]", paste(...), "\n")
sanitize_numeric <- function(x) { x[is.nan(x) | is.infinite(x)] <- NA_real_; x }
pick_first <- function(candidates, pool) { x <- intersect(candidates, pool); if (length(x) == 0) NA_character_ else x[1] }

# ---- Config + Detección de carpeta del código ----
FILE_IN  <- "BBDD Estado Resultado Operacional.xlsx"  # Excel en la MISMA carpeta que este .R
SHEET_IN <- NULL
DIR_OUT  <- "outputs"
if (!dir.exists(DIR_OUT)) dir.create(DIR_OUT, recursive = TRUE)

detect_base_dir <- function() {
  # 1) Si fue llamado con source(), 'ofile' queda disponible
  p <- tryCatch(sys.frames()[[1]]$ofile, error = function(e) "")
  if (!is.null(p) && nzchar(p)) {
    return(normalizePath(dirname(p), winslash = "/"))
  }
  # 2) RStudio (opcional)
  if (requireNamespace("rstudioapi", quietly = TRUE)) {
    ok <- tryCatch(rstudioapi::isAvailable(), error = function(e) FALSE)
    if (isTRUE(ok)) {
      p2 <- tryCatch(rstudioapi::getActiveDocumentContext()$path, error = function(e) "")
      if (!is.null(p2) && nzchar(p2)) {
        return(normalizePath(dirname(p2), winslash = "/"))
      }
    }
  }
  # 3) Fallback: WD
  normalizePath(getwd(), winslash = "/")
}

BASE_DIR  <- detect_base_dir()
FILE_PATH <- normalizePath(file.path(BASE_DIR, FILE_IN), winslash = "/", mustWork = FALSE)
msg("Carpeta base detectada:", BASE_DIR)
msg("Archivo esperado:", FILE_PATH)

if (!file.exists(FILE_PATH)) {
  stop("No se encontró el Excel en la misma carpeta del script.\n",
       "Probé: ", FILE_PATH, "\n",
       "Verifica que el nombre sea exactamente '", FILE_IN, "' y que esté junto a este .R.")
}

# ---- Lectura ----
raw <- if (is.null(SHEET_IN)) readxl::read_excel(FILE_PATH) else readxl::read_excel(FILE_PATH, sheet = SHEET_IN)
raw <- janitor::clean_names(raw)
stopifnot("El Excel se leyó vacío." = nrow(raw) > 0)
msg("Columnas (primeras 30):", paste(head(names(raw), 30), collapse = ", "))

# ---- Detección de columnas clave ----
col_periodo <- pick_first(c("periodo"), names(raw))
stopifnot("No encuentro la columna PERIODO (periodo) en el Excel." = !is.na(col_periodo))

col_pc   <- pick_first(c("pc","profit_center","centro_costo"), names(raw))
col_agru <- pick_first(c("agrupador","hfm_account_text","hfm_account","cuenta","cuenta_texto"), names(raw))
col_desc <- pick_first(c("descripcion","descripción","description"), names(raw))
col_cli  <- pick_first(c("denominacion_cliente","cliente","denominacion_contrato"), names(raw))
col_srv  <- pick_first(c("servicio","lvl2_service","service"), names(raw))
col_n2   <- pick_first(c("n_2","n2"), names(raw))
col_n3   <- pick_first(c("n_3","n3"), names(raw))
stopifnot("No encuentro PC o AGRUPADOR en el Excel." = !is.na(col_pc) && !is.na(col_agru))

# Meses SEP..AGO + YTD
meses_dic  <- c("sep","oct","nov","dic","ene","feb","mar","abr","may","jun","jul","ago")
cols_meses <- names(raw)[tolower(names(raw)) %in% meses_dic]
stopifnot("No se encontraron columnas de meses (Sep..Ago) en el archivo." = length(cols_meses) >= 6)
col_ytd <- pick_first(c("ytd"), names(raw))
stopifnot("No se encontró la columna YTD en el Excel fuente." = !is.na(col_ytd))

msg("PERIODO:", col_periodo, "| PC:", col_pc, "| AGRUP:", col_agru, "| DESC:", col_desc,
    "| CLI:", col_cli, "| SRV:", col_srv, "| N+2:", col_n2, "| N+3:", col_n3, "| YTD:", col_ytd)

# ---- Subset columnas necesarias ----
sel_cols <- unique(na.omit(c(col_pc, col_agru, col_periodo, col_desc, col_cli, col_srv, col_n2, col_n3, col_ytd, cols_meses)))
data <- raw[, sel_cols, drop = FALSE]
msg("Filas iniciales:", nrow(data))

# ---- Filtrar PERIODO (Budget_26 / Real_26 / Real_25) ----
data <- data %>%
  dplyr::mutate(periodo_src = tolower(gsub("\\s+", "", as.character(.data[[col_periodo]])))) %>%
  dplyr::filter(stringr::str_detect(periodo_src, "budget_26|real_26|real_25"))
stopifnot("No hay filas con Budget_26/Real_26/Real_25 en PERIODO." = nrow(data) > 0)

# Normalizar meses a minúsculas sólo para columnas de meses
names(data) <- ifelse(tolower(names(data)) %in% meses_dic, tolower(names(data)), names(data))

# ============================================================
# >>> Adecuación Calendario fiscal Compañia: Sep=1 ... Ago=12 <<<
# ============================================================
meses_fiscal_order <- c("sep","oct","nov","dic","ene","feb","mar","abr","may","jun","jul","ago")
meses_fiscal_num   <- setNames(1:12, meses_fiscal_order)
meses_fiscal_nomb  <- c(
  sep = "Septiembre", oct = "Octubre",   nov = "Noviembre", dic = "Diciembre",
  ene = "Enero",      feb = "Febrero",   mar = "Marzo",     abr = "Abril",
  may = "Mayo",       jun = "Junio",     jul = "Julio",     ago = "Agosto"
)

# ---- Largo (mes -> filas) ----
long <- data %>%
  tidyr::pivot_longer(all_of(tolower(cols_meses)), names_to = "mes_txt", values_to = "monto") %>%
  dplyr::mutate(
    periodo = dplyr::case_when(
      stringr::str_detect(periodo_src, "budget_26") ~ "Budget_26",
      stringr::str_detect(periodo_src, "real_26")   ~ "Real_26",
      stringr::str_detect(periodo_src, "real_25")   ~ "Real_25",
      TRUE ~ NA_character_
    ),
    mes_txt    = tolower(mes_txt),
    mes_num    = as.integer(meses_fiscal_num[ mes_txt ]),   # Sep=1 ... Ago=12
    mes_nombre = meses_fiscal_nomb[ mes_txt ],
    monto      = suppressWarnings(as.numeric(monto))
  ) %>%
  dplyr::filter(!is.na(periodo), !is.na(mes_num))

# ---- Mapear Agrupador (01..09) ----
long <- long %>%
  dplyr::mutate(agrupador_val = as.character(.data[[col_agru]])) %>%
  dplyr::mutate(agrupador_std = dplyr::case_when(
    stringr::str_detect(agrupador_val, "(?i)^\\s*01\\s*.*revenue")            ~ "01_Revenue",
    stringr::str_detect(agrupador_val, "(?i)^\\s*02\\s*.*raw")                ~ "02_RawMaterial",
    stringr::str_detect(agrupador_val, "(?i)^\\s*03\\s*.*purchasing")         ~ "03_PurchasingIncome",
    stringr::str_detect(agrupador_val, "(?i)^\\s*04\\s*.*labou?r")            ~ "04_Labour",
    stringr::str_detect(agrupador_val, "(?i)^\\s*05\\s*.*subcontract")        ~ "05_Subcontract",
    stringr::str_detect(agrupador_val, "(?i)^\\s*06\\s*.*depreci")            ~ "06_Depreciation",
    stringr::str_detect(agrupador_val, "(?i)^\\s*07\\s*.*other.*direct")      ~ "07_OtherDirectCosts",
    stringr::str_detect(agrupador_val, "(?i)^\\s*08\\s*.*bad\\s*debts")       ~ "08_BadDebts",
    stringr::str_detect(agrupador_val, "(?i)^\\s*09\\s*.*gop")                ~ "09_GOP",
    TRUE ~ "OTROS"
  ))

# ---- Etiquetas (opcionales si las columnas existen) ----
safe_col <- function(df, colname) if (!is.na(colname) && colname %in% names(df)) as.character(df[[colname]]) else NA_character_
long <- long %>%
  dplyr::mutate(
    pc          = safe_col(., col_pc),
    descripcion = safe_col(., col_desc),
    cli         = safe_col(., col_cli),
    srv         = safe_col(., col_srv),
    n2          = safe_col(., col_n2),
    n3          = safe_col(., col_n3)
  )

# ---- Venta/GOP mensual ----
venta_pc <- long %>%
  dplyr::filter(agrupador_std == "01_Revenue") %>%
  dplyr::group_by(pc, descripcion, srv, n2, n3, mes_num, mes_nombre, periodo) %>%
  dplyr::summarise(venta = sum(monto, na.rm = TRUE), .groups = "drop")

gop_pc <- long %>%
  dplyr::filter(agrupador_std == "09_GOP") %>%
  dplyr::group_by(pc, descripcion, srv, n2, n3, mes_num, mes_nombre, periodo) %>%
  dplyr::summarise(gop = sum(monto, na.rm = TRUE), .groups = "drop")

gop_pc_full <- venta_pc %>%
  dplyr::full_join(gop_pc, by = c("pc","descripcion","srv","n2","n3","mes_num","mes_nombre","periodo")) %>%
  dplyr::mutate(
    venta   = dplyr::coalesce(venta, 0),
    gop     = dplyr::coalesce(gop,   0),
    gop_pct = dplyr::if_else(venta != 0, gop / venta, NA_real_)
  )

# ---- Clasificación por PC (base sin % mensual; % se calcula YTD) ----
clasif_real26 <- gop_pc_full %>%
  dplyr::filter(periodo == "Real_26") %>%
  dplyr::group_by(pc) %>%
  dplyr::summarise(
    descripcion = dplyr::first(descripcion),
    srv         = dplyr::first(srv),
    n2          = dplyr::first(n2),
    n3          = dplyr::first(n3),
    .groups = "drop"
  )

# ---- YTD por PC (Real_26): Venta y GOP ----
data_map <- data %>%
  dplyr::mutate(agrupador_val = as.character(.data[[col_agru]])) %>%
  dplyr::mutate(agrupador_std = dplyr::case_when(
    stringr::str_detect(agrupador_val, "(?i)^\\s*01\\s*.*revenue") ~ "01_Revenue",
    stringr::str_detect(agrupador_val, "(?i)^\\s*09\\s*.*gop")     ~ "09_GOP",
    TRUE ~ "OTROS"
  )) %>%
  dplyr::mutate(periodo = dplyr::case_when(
    stringr::str_detect(periodo_src, "budget_26") ~ "Budget_26",
    stringr::str_detect(periodo_src, "real_26")   ~ "Real_26",
    stringr::str_detect(periodo_src, "real_25")   ~ "Real_25",
    TRUE ~ NA_character_
  )) %>%
  dplyr::mutate(pc = as.character(.data[[col_pc]]),
                ytd_val = suppressWarnings(as.numeric(.data[[col_ytd]])))

venta_ytd_real26 <- data_map %>%
  dplyr::filter(periodo == "Real_26", agrupador_std == "01_Revenue") %>%
  dplyr::group_by(pc) %>%
  dplyr::summarise(venta_real26_ytd = sum(ytd_val, na.rm = TRUE), .groups = "drop")

gop_ytd_real26 <- data_map %>%
  dplyr::filter(periodo == "Real_26", agrupador_std == "09_GOP") %>%
  dplyr::group_by(pc) %>%
  dplyr::summarise(gop_real26_ytd = sum(ytd_val, na.rm = TRUE), .groups = "drop")

# ---- Resumen (YTD) con categoría ----
resumen <- clasif_real26 %>%
  dplyr::left_join(venta_ytd_real26, by = "pc") %>%
  dplyr::left_join(gop_ytd_real26,  by = "pc") %>%
  dplyr::mutate(
    venta_real26    = dplyr::coalesce(venta_real26_ytd, 0),
    gop_real26      = dplyr::coalesce(gop_real26_ytd,   0),
    gop_pct_real26  = dplyr::if_else(venta_real26 != 0, gop_real26 / venta_real26, NA_real_),
    gop_pct_real26  = sanitize_numeric(gop_pct_real26),
    categoria = dplyr::case_when(
      is.na(gop_pct_real26) ~ NA_character_,
      gop_pct_real26 < 0    ~ "LMC",
      gop_pct_real26 < 0.08 ~ "Low Performance",
      TRUE                  ~ "Profitable"
    )
  ) %>%
  dplyr::select(pc, descripcion, srv, n2, n3, venta_real26, gop_real26, gop_pct_real26, categoria)

# ---- Desviaciones por agrupador (mensual) ----
base_agru <- long %>%
  dplyr::filter(agrupador_std %in% c("01_Revenue","02_RawMaterial","03_PurchasingIncome","04_Labour",
                                     "05_Subcontract","06_Depreciation","07_OtherDirectCosts",
                                     "08_BadDebts","09_GOP")) %>%
  dplyr::group_by(pc, descripcion, srv, n2, n3, mes_num, mes_nombre, agrupador_std, periodo) %>%
  dplyr::summarise(valor = sum(monto, na.rm = TRUE), .groups = "drop")

agru_r26 <- base_agru %>% dplyr::filter(periodo=="Real_26")   %>% dplyr::rename(valor_real26   = valor) %>% dplyr::select(-periodo)
agru_b26 <- base_agru %>% dplyr::filter(periodo=="Budget_26") %>% dplyr::rename(valor_budget26 = valor) %>% dplyr::select(-periodo)
agru_r25 <- base_agru %>% dplyr::filter(periodo=="Real_25")   %>% dplyr::rename(valor_real25   = valor) %>% dplyr::select(-periodo)

desv_agru <- agru_r26 %>%
  dplyr::full_join(agru_b26, by=c("pc","descripcion","srv","n2","n3","mes_num","mes_nombre","agrupador_std")) %>%
  dplyr::full_join(agru_r25, by=c("pc","descripcion","srv","n2","n3","mes_num","mes_nombre","agrupador_std")) %>%
  dplyr::mutate(
    desv_pct_r26_vs_b26 = dplyr::if_else(!is.na(valor_budget26) & valor_budget26 != 0,
                                         (dplyr::coalesce(valor_real26,0) - valor_budget26)/abs(valor_budget26), NA_real_),
    desv_pct_r26_vs_r25 = dplyr::if_else(!is.na(valor_real25) & valor_real25 != 0,
                                         (dplyr::coalesce(valor_real26,0) - valor_real25)/abs(valor_real25), NA_real_)
  ) %>%
  dplyr::mutate(
    desv_pct_r26_vs_b26 = sanitize_numeric(desv_pct_r26_vs_b26),
    desv_pct_r26_vs_r25 = sanitize_numeric(desv_pct_r26_vs_r25)
  )

# ---- Salida a Excel (sin Tablas) ----
out_xlsx <- file.path(DIR_OUT, "MVP_Etapa2_Informe.xlsx")
wb <- openxlsx::createWorkbook()

## 1) Resumen_GOP_PC
openxlsx::addWorksheet(wb, "Resumen_GOP_PC")
openxlsx::writeData(wb, "Resumen_GOP_PC", resumen, withFilter = TRUE)

# Estilos
res_cols <- names(resumen)
col_venta <- which(res_cols == "venta_real26")
col_gop   <- which(res_cols == "gop_real26")
col_pct   <- which(res_cols == "gop_pct_real26")
col_cat   <- which(res_cols == "categoria")

mon_style <- openxlsx::createStyle(numFmt = "\"$\" #,##0")
pct_style <- openxlsx::createStyle(numFmt = "0.0%")
st_rojo    <- openxlsx::createStyle(fgFill = "#FDE7E9")
st_naranja <- openxlsx::createStyle(fgFill = "#FFF2CC")
st_verde   <- openxlsx::createStyle(fgFill = "#E2F0D9")

n_rows_res <- nrow(resumen)

if (length(col_venta) == 1 && n_rows_res > 0) {
  openxlsx::addStyle(wb, "Resumen_GOP_PC", style = mon_style,
                     rows = 2:(n_rows_res+1), cols = col_venta, gridExpand = TRUE)
}
if (length(col_gop) == 1 && n_rows_res > 0) {
  openxlsx::addStyle(wb, "Resumen_GOP_PC", style = mon_style,
                     rows = 2:(n_rows_res+1), cols = col_gop, gridExpand = TRUE)
}
if (length(col_pct) == 1 && n_rows_res > 0) {
  openxlsx::addStyle(wb, "Resumen_GOP_PC", style = pct_style,
                     rows = 2:(n_rows_res+1), cols = col_pct, gridExpand = TRUE)
}

st_txt_rojo  <- openxlsx::createStyle(fontColour = "#9C0006")  # rojo oscuro
st_txt_verde <- openxlsx::createStyle(fontColour = "#006100")  # verde oscuro

# Color directo a la columna 'categoria'
if (length(col_cat) == 1 && n_rows_res > 0) {
  vals <- resumen$categoria
  for (i in seq_len(n_rows_res)) {
    sty <- switch(vals[i],
                  "LMC"             = st_rojo,
                  "Low Performance" = st_naranja,
                  "Profitable"      = st_verde,
                  NULL)
    if (!is.null(sty)) {
      openxlsx::addStyle(wb, "Resumen_GOP_PC", style = sty,
                         rows = i + 1, cols = col_cat, gridExpand = TRUE, stack = TRUE)
    }
  }
}
openxlsx::freezePane(wb, "Resumen_GOP_PC", firstRow = TRUE)

## 2) Desv_Agrupador
openxlsx::addWorksheet(wb, "Desv_Agrupador")
desv_view <- desv_agru %>% dplyr::arrange(pc, mes_num, agrupador_std)
openxlsx::writeData(wb, "Desv_Agrupador", desv_view, withFilter = TRUE)

desv_cols <- names(desv_view)
col_dv_b  <- which(desv_cols == "desv_pct_r26_vs_b26")
col_dv_r  <- which(desv_cols == "desv_pct_r26_vs_r25")
col_val_r26 <- which(desv_cols == "valor_real26")
col_val_b26 <- which(desv_cols == "valor_budget26")
col_val_r25 <- which(desv_cols == "valor_real25")

n_rows_dv <- nrow(desv_view)
if (length(col_dv_b) == 1 && n_rows_dv > 0) {
  openxlsx::addStyle(wb, "Desv_Agrupador", style = pct_style,
                     rows = 2:(n_rows_dv+1), cols = col_dv_b, gridExpand = TRUE)
}
if (length(col_dv_r) == 1 && n_rows_dv > 0) {
  openxlsx::addStyle(wb, "Desv_Agrupador", style = pct_style,
                     rows = 2:(n_rows_dv+1), cols = col_dv_r, gridExpand = TRUE)
}
for (cc in c(col_val_r26, col_val_b26, col_val_r25)) {
  if (length(cc) == 1 && n_rows_dv > 0) {
    openxlsx::addStyle(wb, "Desv_Agrupador", style = mon_style,
                       rows = 2:(n_rows_dv+1), cols = cc, gridExpand = TRUE)
  }
}

# Cambiar color de la letra según signo en 'desv_pct_r26_vs_b26'
if (length(col_dv_b) == 1 && n_rows_dv > 0) {
  rng_rows   <- 2:(n_rows_dv + 1)
  col_letter <- openxlsx::int2col(col_dv_b)
  
  # Texto rojo si < 0
  openxlsx::conditionalFormatting(
    wb, sheet = "Desv_Agrupador",
    cols = col_dv_b, rows = rng_rows,
    type = "expression",
    rule = paste0("=", col_letter, "2<0"),
    style = st_txt_rojo
  )
  
  # Texto verde si > 0
  openxlsx::conditionalFormatting(
    wb, sheet = "Desv_Agrupador",
    cols = col_dv_b, rows = rng_rows,
    type = "expression",
    rule = paste0("=", col_letter, "2>0"),
    style = st_txt_verde
  )
}


openxlsx::freezePane(wb, "Desv_Agrupador", firstRow = TRUE)


## 3) GOP_Mensual
openxlsx::addWorksheet(wb, "GOP_Mensual")
gop_mensual <- gop_pc_full %>%
  dplyr::arrange(pc, mes_num, periodo) %>%
  dplyr::mutate(gop_pct = sanitize_numeric(gop_pct))
openxlsx::writeData(wb, "GOP_Mensual", gop_mensual, withFilter = TRUE)

gm_cols <- names(gop_mensual)
col_gm_pct  <- which(gm_cols == "gop_pct")
col_gm_gop  <- which(gm_cols == "gop")
col_gm_vent <- which(gm_cols == "venta")
n_rows_gm <- nrow(gop_mensual)

if (length(col_gm_pct) == 1 && n_rows_gm > 0) {
  openxlsx::addStyle(wb, "GOP_Mensual", style = pct_style,
                     rows = 2:(n_rows_gm+1), cols = col_gm_pct, gridExpand = TRUE)
}
for (cc in c(col_gm_gop, col_gm_vent)) {
  if (length(cc) == 1 && n_rows_gm > 0) {
    openxlsx::addStyle(wb, "GOP_Mensual", style = mon_style,
                       rows = 2:(n_rows_gm+1), cols = cc, gridExpand = TRUE)
  }
}
openxlsx::freezePane(wb, "GOP_Mensual", firstRow = TRUE)

## 4) Guia
openxlsx::addWorksheet(wb, "Guia")
guia <- c(
  "MVP Etapa 2 - Estado de Resultados (PC / Mes / Periodo)",
  "- Periodos: Budget_26, Real_26, Real_25.",
  "- Calendario fiscal: Sep=1, Oct=2, Nov=3, Dic=4, Ene=5, Feb=6, Mar=7, Abr=8, May=9, Jun=10, Jul=11, Ago=12.",
  "- Venta = 01 Revenue; GOP = 09 GOP; GOP% = GOP / Venta.",
  "- En 'Resumen_GOP_PC': GOP% YTD = GOP_YTD / Venta_YTD; Categoría coloreada (LMC/Low Performance/Profitable).",
  "- En 'Desv_Agrupador' y 'GOP_Mensual': se muestra 'mes_num' fiscal y 'mes_nombre'.",
  "- Formatos: moneda para montos y porcentaje para desvíos y GOP%."
)
openxlsx::writeData(wb, "Guia", guia)


# --- Detecta carpeta del script ---
detect_base_dir <- function() {
  p <- tryCatch(sys.frames()[[1]]$ofile, error = function(e) "")
  if (!is.null(p) && nzchar(p)) return(normalizePath(dirname(p), winslash = "/"))
  if (requireNamespace("rstudioapi", quietly = TRUE)) {
    ok <- tryCatch(rstudioapi::isAvailable(), error = function(e) FALSE)
    if (isTRUE(ok)) {
      p2 <- tryCatch(rstudioapi::getActiveDocumentContext()$path, error = function(e) "")
      if (!is.null(p2) && nzchar(p2)) return(normalizePath(dirname(p2), winslash = "/"))
    }
  }
  normalizePath(getwd(), winslash = "/")
}
BASE_DIR <- detect_base_dir()

# --- Guardar SIEMPRE en una subcarpeta ejemplo: "outputs" al lado del código
DIR_OUT <- file.path(BASE_DIR, "outputs")  # <-- clave: depende de BASE_DIR, no del WD
if (!dir.exists(DIR_OUT)) dir.create(DIR_OUT, recursive = TRUE)

out_xlsx <- file.path(DIR_OUT, "MVP_Etapa2_Informe.xlsx")

# (procede a almacenar el código)
openxlsx::saveWorkbook(wb, out_xlsx, overwrite = TRUE)
cat("[INFO] Guardado en:", out_xlsx, "\n")


# Guardar
openxlsx::saveWorkbook(wb, out_xlsx, overwrite = TRUE)
msg("Listo ->", out_xlsx)