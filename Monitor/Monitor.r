# ============================================================
# monitor/monitor.R  —  Monitoreo de datos y agregados de control
# ============================================================

suppressPackageStartupMessages({
  library(readxl); library(dplyr); library(tidyr); library(stringr); library(janitor)
})

cat("\n[MONITOR] Iniciando chequeos...\n")

# --- Detectar carpeta base del proyecto (funciona desde raíz o desde /monitor) ---
detect_base_dir <- function() {
  # 1) Si se está ejecutando con source(), intentar ofile
  p <- tryCatch(sys.frames()[[1]]$ofile, error = function(e) "")
  if (!is.null(p) && nzchar(p)) {
    # Si p = .../monitor/monitor.R -> base = dirname(dirname(p))
    return(normalizePath(dirname(dirname(p)), winslash = "/"))
  }
  # 2) RStudio: documento activo
  if (requireNamespace("rstudioapi", quietly = TRUE)) {
    ok <- tryCatch(rstudioapi::isAvailable(), error = function(e) FALSE)
    if (isTRUE(ok)) {
      p2 <- tryCatch(rstudioapi::getActiveDocumentContext()$path, error = function(e) "")
      if (!is.null(p2) && nzchar(p2)) {
        # Si estás editando monitor.R, dirname(p2) = .../monitor -> subimos
        return(normalizePath(dirname(dirname(p2)), winslash = "/"))
      }
    }
  }
  # 3) Fallback: si ya estás en raíz del proyecto
  normalizePath(getwd(), winslash = "/")
}

BASE_DIR <- detect_base_dir()
cat("[MONITOR] Carpeta base detectada:", BASE_DIR, "\n")

# --- Rutas de trabajo ---
FILE_EXCEL <- file.path(BASE_DIR, "BBDD Estado Resultado Operacional.xlsx")
OUT_DIR    <- file.path(BASE_DIR, "monitor", "outputs")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("[MONITOR] Excel:", FILE_EXCEL, "\n")
stopifnot(file.exists(FILE_EXCEL))

# --- Lectura y normalización básica ---
raw <- readxl::read_excel(FILE_EXCEL) |> janitor::clean_names()

# Mapear alias de N+2 / N+3 si existen (no falla si no están)
alias_n2 <- c("n2","n_2","nivel2")
alias_n3 <- c("n3","n_3","nivel3")
col_n2 <- intersect(alias_n2, names(raw))
col_n3 <- intersect(alias_n3, names(raw))
if (length(col_n2) >= 1) names(raw)[match(col_n2[1], names(raw))] <- "n2"
if (length(col_n3) >= 1) names(raw)[match(col_n3[1], names(raw))] <- "n3"

issues <- c()

# 1) Check filas
if (nrow(raw) < 50) issues <- c(issues, sprintf("Advertencia: pocas filas en el Excel (%s filas).", nrow(raw)))

# 2) Check columnas (OBLIGATORIAS y OPCIONALES)
required_cols <- c("periodo","agrupador","pc","descripcion")
missing_req <- required_cols[!required_cols %in% names(raw)]
if (length(missing_req) > 0) {
  issues <- c(issues, paste("Faltan columnas OBLIGATORIAS:", paste(missing_req, collapse=", ")))
}

# Opcionales N+2/N+3, solo informar
opt_present <- intersect(c("n2","n3"), names(raw))
if (length(opt_present) == 0) {
  issues <- c(issues, "Nota: no se detectaron columnas N+2/N+3 (opcional).")
}

# 3) Check meses SEP..AGO
meses_dic <- c("sep","oct","nov","dic","ene","feb","mar","abr","may","jun","jul","ago")
# Si vinieran en mayúsculas (SEP), este monitor no renombra, solo detecta presentes
found_meses <- meses_dic[meses_dic %in% names(raw)]
if (length(found_meses) < 6) {
  issues <- c(issues, sprintf("Advertencia: solo %s columnas de meses detectadas (Sep..Ago).", length(found_meses)))
}

# 4) Parseo numérico básico en meses
if (length(found_meses) > 0) {
  nums <- suppressWarnings(as.numeric(unlist(raw[,found_meses])))
  na_rate <- mean(is.na(nums))
  if (is.finite(na_rate) && na_rate > 0.05) {
    issues <- c(issues, paste0("Más de 5% de NA después de parseo numérico en meses: ", round(na_rate*100,1), "%"))
  }
}

# 5) Duplicados exactos
dups <- sum(duplicated(raw))
if (dups > 0) issues <- c(issues, paste("Hay filas duplicadas exactas:", dups))

# ============================================================
# 🆕 AGREGADOS DE CONTROL: ΣVenta y ΣGOP por mes y periodo
# ============================================================

# Mapeo calendario fiscal (para ordenar)
meses_fiscal_order <- c("sep","oct","nov","dic","ene","feb","mar","abr","may","jun","jul","ago")
meses_fiscal_num   <- setNames(1:12, meses_fiscal_order)
meses_fiscal_nomb  <- c(
  sep="Septiembre", oct="Octubre", nov="Noviembre", dic="Diciembre",
  ene="Enero", feb="Febrero", mar="Marzo", abr="Abril",
  may="Mayo", jun="Junio", jul="Julio", ago="Agosto"
)

# Periodos flexibles
periodo_from_src <- function(x) {
  xs <- tolower(gsub("\\s+", "", as.character(x)))
  dplyr::case_when(
    stringr::str_detect(xs, "budget[_-]?26") ~ "Budget_26",
    stringr::str_detect(xs, "real[_-]?26")   ~ "Real_26",
    stringr::str_detect(xs, "real[_-]?25")   ~ "Real_25",
    TRUE ~ NA_character_
  )
}

# Función de parseo robusto (coma/punto)
parse_num <- function(x) {
  if (is.numeric(x)) return(x)
  x <- as.character(x)
  x <- gsub("\u00A0", " ", x, fixed = TRUE)           # NBSP
  x <- trimws(x)
  has_comma_dec <- grepl(",\\d{1,2}$", x)
  x[has_comma_dec] <- gsub("\\.", "", x[has_comma_dec])
  x[has_comma_dec] <- gsub(",", ".", x[has_comma_dec])
  has_dot_dec <- grepl("\\.\\d{1,2}$", x)
  x[has_dot_dec] <- gsub(",", "", x[has_dot_dec])
  suppressWarnings(as.numeric(x))
}

# Pivot a largo SOLO si hay columnas de meses detectadas
agg_out <- NULL
if (length(found_meses) > 0) {
  long <- raw %>%
    tidyr::pivot_longer(all_of(found_meses), names_to = "mes_txt", values_to = "monto_raw") %>%
    dplyr::mutate(
      periodo = periodo_from_src(.data$periodo),
      mes_txt = tolower(mes_txt),
      mes_num = as.integer(meses_fiscal_num[ mes_txt ]),
      mes_nombre = meses_fiscal_nomb[ mes_txt ],
      monto = parse_num(monto_raw),
      agrupador_val = as.character(.data$agrupador)
    ) %>%
    dplyr::filter(!is.na(periodo), !is.na(mes_num)) %>%
    dplyr::mutate(
      agrupador_std = dplyr::case_when(
        stringr::str_detect(agrupador_val, "(?i)^\\s*01\\s*.*revenue") ~ "01_Revenue",
        stringr::str_detect(agrupador_val, "(?i)^\\s*09\\s*.*gop")     ~ "09_GOP",
        TRUE ~ "OTROS"
      )
    )
  
  # Σ por mes / periodo y métricas clave
  agg <- long %>%
    dplyr::filter(agrupador_std %in% c("01_Revenue","09_GOP")) %>%
    dplyr::group_by(mes_num, mes_nombre, periodo, agrupador_std) %>%
    dplyr::summarise(valor = sum(monto, na.rm = TRUE), .groups = "drop") %>%
    tidyr::pivot_wider(names_from = agrupador_std, values_from = valor, values_fill = 0) %>%
    dplyr::arrange(mes_num, periodo) %>%
    dplyr::mutate(
      venta_total = `01_Revenue`,
      gop_total   = `09_GOP`,
      gop_pct     = dplyr::if_else(venta_total != 0, gop_total / venta_total, NA_real_)
    ) %>%
    dplyr::select(mes_num, mes_nombre, periodo, venta_total, gop_total, gop_pct)
  
  # Guardar CSV con sello de tiempo
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out_csv <- file.path(OUT_DIR, paste0("agg_control_", stamp, ".csv"))
  readr::write_csv(agg, out_csv)
  agg_out <- out_csv
  cat("[MONITOR] Archivo de control escrito en:", out_csv, "\n")
  
  # Heurística: signo de Budget (si >80% negativo, avisar)
  budget_neg_ratio <- agg %>%
    dplyr::filter(periodo == "Budget_26") %>%
    dplyr::summarise(r = mean(gop_total < 0, na.rm = TRUE)) %>% dplyr::pull(r)
  if (!is.na(budget_neg_ratio) && budget_neg_ratio > 0.8) {
    issues <- c(issues, sprintf("GOP Budget negativo en %.0f%% de los meses (posible inversión de signo).", 100*budget_neg_ratio))
  }
} else {
  cat("[MONITOR] No se generó agregación porque no se detectaron columnas de meses.\n")
}

# --- Log final ---
if (length(issues) == 0) {
  cat("[MONITOR] OK - No se detectaron problemas importantes.\n")
} else {
  cat("[MONITOR] Problemas/Notas detectadas:\n")
  for (i in issues) cat(" -", i, "\n")
}

if (!is.null(agg_out)) {
  cat("[MONITOR] Tip: abre el CSV de control para conciliar (ΣVenta, ΣGOP, GOP%).\n")
}

cat("[MONITOR] Finalizado.\n")