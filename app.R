# ===============================================
#FEN UCHILE
#ETAPA 2 PROYECTO EN CURSO
# MVP Etapa 2 - Estado de Resultados por PC (Periodo, Venta y GOP, Acumulado anual Year to Day YTD )
# APP.R - Interfaz Shiny para Finanzas (Filtros y Gráficos)
# Autor: Benazir Maria Castillo Rivas
# Profesor: Sebastian Egaña
# ===============================================

#Consideraciones de la Data: Graficos con info a Diciembre 2025, por ende no existe data Real para Enero 26 en adelante.

options(stringsAsFactors = FALSE)

# ---- Instalación de Paquetes ----
pkgs <- c("shiny","readxl","dplyr","tidyr","stringr","janitor","ggplot2","scales","forcats")
to_install <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(to_install)) install.packages(to_install, repos = "https://cloud.r-project.org")
invisible(lapply(pkgs, library, character.only = TRUE))

# ---- Helpers ----
msg  <- function(...) cat("[INFO]", paste(...), "\n")
sanitize_numeric <- function(x) { x[is.nan(x) | is.infinite(x)] <- NA_real_; x }
pick_first <- function(candidates, pool) { x <- intersect(candidates, pool); if (length(x) == 0) NA_character_ else x[1] }
is_empty <- function(x) is.null(x) || length(x) == 0

# ---- Configuración y Detección de carpeta del código ----
FILE_IN  <- "BBDD Estado Resultado Operacional.xlsx"  # Excel en la MISMA carpeta que este app.R
SHEET_IN <- NULL

detect_base_dir <- function() {
  # 1) Si fue llamado con source(), 'ofile' queda disponible
  p <- tryCatch(sys.frames()[[1]]$ofile, error = function(e) "")
  if (!is.null(p) && nzchar(p)) return(normalizePath(dirname(p), winslash = "/"))
  # 2) RStudio (opcional)
  if (requireNamespace("rstudioapi", quietly = TRUE)) {
    ok <- tryCatch(rstudioapi::isAvailable(), error = function(e) FALSE)
    if (isTRUE(ok)) {
      p2 <- tryCatch(rstudioapi::getActiveDocumentContext()$path, error = function(e) "")
      if (!is.null(p2) && nzchar(p2)) return(normalizePath(dirname(p2), winslash = "/"))
    }
  }
  # 3) Fallback: WD
  normalizePath(getwd(), winslash = "/")
}
BASE_DIR  <- detect_base_dir()
FILE_PATH <- normalizePath(file.path(BASE_DIR, FILE_IN), winslash = "/", mustWork = FALSE)
msg("Carpeta base detectada:", BASE_DIR)
msg("Archivo esperado:", FILE_PATH)
if (!file.exists(FILE_PATH)) stop("No se encontró el Excel en la misma carpeta del app.\nProbé: ", FILE_PATH)

# ---- Lectura y preparación ----
raw <- if (is.null(SHEET_IN)) readxl::read_excel(FILE_PATH) else readxl::read_excel(FILE_PATH, sheet = SHEET_IN)
raw <- janitor::clean_names(raw)
stopifnot("El Excel se leyó vacío." = nrow(raw) > 0)

# Meses considerados (fiscal Sep..Ago)
meses_dic <- c("sep","oct","nov","dic","ene","feb","mar","abr","may","jun","jul","ago")

# Normalizar SOLO columnas de meses a minúsculas (para asegurar 'sep','oct', etc.)
names(raw) <- ifelse(tolower(names(raw)) %in% meses_dic, tolower(names(raw)), names(raw))

# Columnas clave
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

# Meses SEP..AGO + YTD (tras normalizar nombres)
cols_meses <- names(raw)[names(raw) %in% meses_dic]
stopifnot("No se encontraron columnas de meses (Sep..Ago) en el archivo." = length(cols_meses) >= 6)
col_ytd <- pick_first(c("ytd"), names(raw))
stopifnot("No se encontró la columna YTD en el Excel fuente." = !is.na(col_ytd))

# Subset + periodos
data <- raw[, unique(na.omit(c(col_pc, col_agru, col_periodo, col_desc, col_cli, col_srv, col_n2, col_n3, col_ytd, cols_meses))), drop = FALSE] %>%
  dplyr::mutate(periodo_src = tolower(gsub("\\s+", "", as.character(.data[[col_periodo]])))) %>%
  dplyr::filter(stringr::str_detect(periodo_src, "budget_26|real_26|real_25"))

# Calendario fiscal
meses_fiscal_order <- c("sep","oct","nov","dic","ene","feb","mar","abr","may","jun","jul","ago")
meses_fiscal_num   <- setNames(1:12, meses_fiscal_order)
meses_fiscal_nomb  <- c(
  sep = "Septiembre", oct = "Octubre",   nov = "Noviembre", dic = "Diciembre",
  ene = "Enero",      feb = "Febrero",   mar = "Marzo",     abr = "Abril",
  may = "Mayo",       jun = "Junio",     jul = "Julio",     ago = "Agosto"
)

# Pasar a largo y estandarizar agrupadores
long <- data %>%
  tidyr::pivot_longer(all_of(cols_meses), names_to = "mes_txt", values_to = "monto") %>%
  dplyr::mutate(
    periodo = dplyr::case_when(
      stringr::str_detect(periodo_src, "budget_26") ~ "Budget_26",
      stringr::str_detect(periodo_src, "real_26")   ~ "Real_26",
      stringr::str_detect(periodo_src, "real_25")   ~ "Real_25",
      TRUE ~ NA_character_
    ),
    mes_txt    = tolower(mes_txt),
    mes_num    = as.integer(meses_fiscal_num[ mes_txt ]),
    mes_nombre = meses_fiscal_nomb[ mes_txt ],
    monto      = suppressWarnings(as.numeric(monto)),
    pc         = if (!is.na(col_pc))  as.character(.data[[col_pc]]) else NA_character_,
    descripcion= if (!is.na(col_desc))as.character(.data[[col_desc]]) else NA_character_,
    cli        = if (!is.na(col_cli)) as.character(.data[[col_cli]]) else NA_character_,
    srv        = if (!is.na(col_srv)) as.character(.data[[col_srv]]) else NA_character_,
    n2         = if (!is.na(col_n2))  as.character(.data[[col_n2]])  else NA_character_,
    n3         = if (!is.na(col_n3))  as.character(.data[[col_n3]])  else NA_character_
  ) %>%
  dplyr::filter(!is.na(periodo), !is.na(mes_num)) %>%
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

# Dataset base de Venta y GOP mensual (por periodo)
venta_pc <- long %>%
  dplyr::filter(agrupador_std == "01_Revenue") %>%
  dplyr::group_by(pc, descripcion, n2, n3, mes_num, mes_nombre, periodo) %>%
  dplyr::summarise(venta = sum(monto, na.rm = TRUE), .groups = "drop")

gop_pc <- long %>%
  dplyr::filter(agrupador_std == "09_GOP") %>%
  dplyr::group_by(pc, descripcion, n2, n3, mes_num, mes_nombre, periodo) %>%
  dplyr::summarise(gop = sum(monto, na.rm = TRUE), .groups = "drop")

gop_pc_full <- venta_pc %>%
  dplyr::full_join(gop_pc, by = c("pc","descripcion","n2","n3","mes_num","mes_nombre","periodo")) %>%
  dplyr::mutate(
    venta   = dplyr::coalesce(venta, 0),
    gop     = dplyr::coalesce(gop,   0),
    gop_pct = dplyr::if_else(venta != 0, gop / venta, NA_real_)
  )

# ---- Choices para UI ----
choices_n3   <- sort(unique(na.omit(long$n3)))
choices_n2   <- sort(unique(na.omit(long$n2)))
choices_desc <- sort(unique(na.omit(long$descripcion)))
choices_pc   <- sort(unique(na.omit(long$pc)))
choices_mes  <- unique(long[, c("mes_num","mes_nombre")]) %>% dplyr::arrange(mes_num) %>% dplyr::pull(mes_nombre)

# ============================================================
# UI
# ============================================================
ui <- fluidPage(
  titlePanel("Estado de Resultados - Filtros y Gráficos"),
  
  sidebarLayout(
    sidebarPanel(
      h4("Filtros"),
      checkboxInput("multi_desc_pc", "Descripción/PC: selección múltiple", value = TRUE),
      checkboxInput("multi_mes",      "Mes: selección múltiple", value = TRUE),
      
      selectizeInput("n3", "N+3", choices = choices_n3, multiple = TRUE, options = list(placeholder = "Selecciona N+3...")),
      selectizeInput("n2", "N+2", choices = choices_n2, multiple = TRUE, options = list(placeholder = "Selecciona N+2...")),
      
      # Descripción o PC (basta una de las dos)
      selectizeInput("desc", "Descripción (opcional)", choices = choices_desc, multiple = TRUE,
                     options = list(placeholder = "Selecciona una o más Descripciones...")),
      selectizeInput("pc", "PC (opcional)", choices = choices_pc, multiple = TRUE,
                     options = list(placeholder = "Selecciona uno o más PCs...")),
      
      selectizeInput("mes", "Mes (fiscal)", choices = choices_mes, multiple = TRUE,
                     options = list(placeholder = "Selecciona meses...")),
      
      helpText("Tip: Si no seleccionas Descripción ni PC, se consideran todas. Si eliges en ambas, se aplica lógica OR (coincidir con una u otra).")
    ),
    
    mainPanel(
      h4("Real 26 vs Budget 26 — Venta y GOP (por mes)"),
      plotOutput("plot_rb_venta_gop", height = "420px"),
      br(),
      h4("Tendencia GOP% — Real 26 vs Budget 26 (por mes)"),
      plotOutput("plot_trend_gop_pct", height = "420px")
    )
  )
)

# ============================================================
# SERVER
# ============================================================
server <- function(input, output, session) {
  
  # Cambiar modo de selección (única/múltiple)
  observeEvent(input$multi_desc_pc, {
    maxItems <- if (isTRUE(input$multi_desc_pc)) 10000 else 1
    updateSelectizeInput(session, "desc", options = list(maxItems = maxItems))
    updateSelectizeInput(session, "pc",   options = list(maxItems = maxItems))
  }, ignoreInit = TRUE)
  
  observeEvent(input$multi_mes, {
    maxItems <- if (isTRUE(input$multi_mes)) 10000 else 1
    updateSelectizeInput(session, "mes", options = list(maxItems = maxItems))
  }, ignoreInit = TRUE)
  
  # Datos filtrados (OR entre Descripción y PC)
  filtered_df <- reactive({
    df <- gop_pc_full
    
    if (!is_empty(input$n3)) df <- df %>% dplyr::filter(n3 %in% input$n3)
    if (!is_empty(input$n2)) df <- df %>% dplyr::filter(n2 %in% input$n2)
    if (!is_empty(input$mes)) df <- df %>% dplyr::filter(mes_nombre %in% input$mes)
    
    if (!is_empty(input$desc) || !is_empty(input$pc)) {
      keep_desc <- if (!is_empty(input$desc)) (df$descripcion %in% input$desc) else rep(FALSE, nrow(df))
      keep_pc   <- if (!is_empty(input$pc))   (df$pc %in% input$pc)           else rep(FALSE, nrow(df))
      df <- df[ keep_desc | keep_pc, , drop = FALSE ]
    }
    
    # Orden de meses (fiscal)
    orden_meses <- unique(long[, c("mes_num","mes_nombre")]) %>%
      dplyr::arrange(mes_num) %>% dplyr::pull(mes_nombre)
    df$mes_nombre <- factor(df$mes_nombre, levels = orden_meses, ordered = TRUE)
    df
  })
  
  # ---- Gráfico: Real 26 vs Budget 26 — Venta y GOP (robusto) ----
  output$plot_rb_venta_gop <- renderPlot({
    df <- filtered_df()
    validate(need(nrow(df) > 0, "No hay datos para los filtros seleccionados."))
    
    # Agregar por mes y periodo (suma de lo filtrado)
    agg <- df %>%
      dplyr::filter(periodo %in% c("Real_26","Budget_26")) %>%
      dplyr::group_by(mes_nombre, periodo) %>%
      dplyr::summarise(
        venta_total = sum(venta, na.rm = TRUE),
        gop_total   = sum(gop,   na.rm = TRUE),
        .groups = "drop"
      )
    validate(need(nrow(agg) > 0, "No hay datos de Real 26 o Budget 26 para graficar."))
    
    # Construir largo sin pivot_longer (evita errores de tipos)
    venta_df <- agg %>%
      dplyr::transmute(mes_nombre, periodo, metric = "Venta", valor = as.numeric(venta_total))
    gop_df <- agg %>%
      dplyr::transmute(mes_nombre, periodo, metric = "GOP", valor = as.numeric(gop_total))
    sum_df <- dplyr::bind_rows(venta_df, gop_df)
    
    # Orden fiscal y etiquetas
    orden_meses <- unique(long[, c("mes_num","mes_nombre")]) %>% dplyr::arrange(mes_num) %>% dplyr::pull(mes_nombre)
    sum_df <- sum_df %>%
      dplyr::mutate(
        mes_nombre = factor(mes_nombre, levels = orden_meses, ordered = TRUE),
        periodo_lbl = dplyr::recode(periodo, "Real_26" = "Real 26", "Budget_26" = "Budget 26"),
        metric = factor(metric, levels = c("Venta","GOP"))
      )
    
    pal <- c("Budget 26" = "grey70", "Real 26" = "#1f77b4")
    
    ggplot2::ggplot(sum_df, ggplot2::aes(x = mes_nombre, y = valor, fill = periodo_lbl)) +
      ggplot2::geom_col(position = ggplot2::position_dodge2(width = 0.8, preserve = "total"), width = 0.75) +
      ggplot2::facet_wrap(~ metric, scales = "free_y") +
      ggplot2::scale_fill_manual(values = pal, drop = FALSE) +
      ggplot2::scale_y_continuous(labels = scales::comma) +
      ggplot2::labs(
        x = "Mes (Fiscal)", y = "Monto",
        title = "Comparación Real 26 vs Budget 26",
        subtitle = "Venta y GOP agregados por mes (sobre la selección)",
        fill = "Periodo"
      ) +
      ggplot2::theme_minimal(base_size = 12) +
      ggplot2::theme(
        legend.position = "top",
        axis.title.x = ggplot2::element_text(margin = ggplot2::margin(t = 8)),
        axis.title.y = ggplot2::element_text(margin = ggplot2::margin(r = 8))
      )
  })
  
  # ---- Gráfico: Tendencia GOP% — Real 26 vs Budget 26 ----
  output$plot_trend_gop_pct <- renderPlot({
    df <- filtered_df()
    validate(need(nrow(df) > 0, "No hay datos para los filtros seleccionados."))
    
    pct_df <- df %>%
      dplyr::filter(periodo %in% c("Real_26","Budget_26")) %>%
      dplyr::group_by(mes_nombre, periodo) %>%
      dplyr::summarise(
        venta_total = sum(venta, na.rm = TRUE),
        gop_total   = sum(gop,   na.rm = TRUE),
        .groups = "drop"
      ) %>%
      dplyr::mutate(
        gop_pct = dplyr::if_else(venta_total != 0, gop_total / venta_total, NA_real_),
        gop_pct = sanitize_numeric(gop_pct),
        periodo_lbl = dplyr::recode(periodo, "Real_26" = "Real 26", "Budget_26" = "Budget 26")
      )
    validate(need(nrow(pct_df) > 0, "No hay datos de Real 26 o Budget 26 para graficar."))
    
    ggplot2::ggplot(pct_df, ggplot2::aes(x = mes_nombre, y = gop_pct, color = periodo_lbl, group = periodo_lbl)) +
      ggplot2::geom_line(linewidth = 1) +
      ggplot2::geom_point(size = 2) +
      ggplot2::scale_y_continuous(labels = scales::percent_format(accuracy = 0.1), limits = c(NA, NA)) +
      ggplot2::scale_color_manual(values = c("Budget 26" = "grey40", "Real 26" = "#d62728"), drop = FALSE) +
      ggplot2::labs(
        x = "Mes (Fiscal)", y = "GOP %",
        title = "Tendencia GOP% — Real 26 vs Budget 26",
        caption = "GOP% = GOP / Venta (agregado por mes sobre la selección)"
      ) +
      ggplot2::theme_minimal(base_size = 12) +
      ggplot2::theme(
        legend.position = "top",
        axis.title.x = ggplot2::element_text(margin = ggplot2::margin(t = 8)),
        axis.title.y = ggplot2::element_text(margin = ggplot2::margin(r = 8))
      )
  })
}

# ---- Lanzar App ----
shinyApp(ui, server)