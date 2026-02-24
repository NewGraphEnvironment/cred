# review.R — interactive Shiny review app for citation audit CSVs

#' Launch an interactive review app for the citation audit CSV
#'
#' Opens a local Shiny app in your browser. Click any row to see the full
#' `paraphrase` and `quote` side by side, set `verified` from a dropdown,
#' add `notes`, and save changes back to the CSV. The CSV remains the source
#' of truth — git history is preserved.
#'
#' @section Workflow:
#' 1. Filter to `"auto"` rows (default on open).
#' 2. Click a row — full paraphrase and quote appear below.
#' 3. Read both, set `verified` to `yes` / `no` / `corrected` / `context`.
#' 4. Add a `notes` entry if the claim needs correction or explanation.
#' 5. Click **Update row** to apply, then **Save to CSV** when done.
#'
#' @param audit_file `character(1)` path to the audit CSV produced by
#'   [crd_aud_write()].
#' @param launch.browser `logical(1)` open the app in the system browser.
#'   Default `TRUE`.
#' @return Called for side effects. Writes to `audit_file` on Save.
#' @export
#' @examples
#' \dontrun{
#' crd_aud_review("background/citation_audit.csv")
#' }
crd_aud_review <- function(audit_file, launch.browser = TRUE) {
  chk::chk_file(audit_file)
  for (pkg in c("shiny", "DT")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("Package '", pkg, "' is required. Install with: pak::pak('", pkg, "')")
    }
  }

  status_colours <- c(
    auto      = "#FFF2CC",
    yes       = "#D9EAD3",
    no        = "#F4CCCC",
    corrected = "#FCE5CD",
    no_match  = "#E2EFDA",
    context   = "#CFE2F3"
  )

  ui <- shiny::fluidPage(
    shiny::tags$head(shiny::tags$style(shiny::HTML("
      body { font-size: 13px; font-family: 'Aptos Narrow', sans-serif; }
      .topbar { background:#1a1a1a; color:white; padding:8px 16px;
                display:flex; align-items:center; gap:16px;
                margin:-15px -15px 14px -15px; }
      .topbar .prog { margin-left:auto; font-size:12px; color:#aaa; }
      .topbar .savemsg { font-size:12px; color:#aaa; }
      .detail-box { background:#f5f5f5; border:1px solid #ddd; border-radius:4px;
                    padding:10px 12px; font-size:13px; line-height:1.55;
                    min-height:72px; white-space:pre-wrap; word-break:break-word; }
      .col-lbl { font-size:10px; font-weight:700; color:#777;
                 text-transform:uppercase; letter-spacing:.04em; margin-bottom:5px; }
      .no-quote { color:#aaa; font-style:italic; }
      hr { margin: 10px 0; }
    "))),

    # Top bar
    shiny::div(class = "topbar",
      shiny::actionButton("save_btn", "Save to CSV",
        class = "btn-success btn-sm"),
      shiny::uiOutput("save_msg"),
      shiny::div(class = "prog", shiny::textOutput("progress", inline = TRUE))
    ),

    # Filters
    shiny::fluidRow(
      shiny::column(3,
        shiny::selectInput("f_status", "Status:",
          choices  = c("auto", "no_match", "corrected", "no",
                       "context", "yes", "(NA)" = "NA_", "All" = "all"),
          selected = "auto", width = "100%")
      ),
      shiny::column(4,
        shiny::selectInput("f_key", "Citation key:",
          choices = "all", selected = "all", width = "100%")
      ),
      shiny::column(3,
        shiny::selectInput("f_section", "Section:",
          choices = "all", selected = "all", width = "100%")
      ),
      shiny::column(2,
        shiny::br(),
        shiny::checkboxInput("hide_done", "Hide yes / corrected", FALSE)
      )
    ),

    # Table
    DT::DTOutput("tbl"),

    shiny::hr(),

    # Detail panel
    shiny::uiOutput("detail")
  )

  server <- function(input, output, session) {

    dat     <- shiny::reactiveVal(
      readr::read_csv(audit_file, show_col_types = FALSE)
    )
    unsaved   <- shiny::reactiveVal(FALSE)
    last_save <- shiny::reactiveVal(NULL)

    # Populate filter dropdowns from data
    shiny::observe({
      d <- dat()
      shiny::updateSelectInput(session, "f_key",
        choices = c("all", sort(unique(d$citation_key[!is.na(d$citation_key)]))))
      shiny::updateSelectInput(session, "f_section",
        choices = c("all", sort(unique(d$section[!is.na(d$section)]))))
    })

    # Filtered rows for table
    filtered <- shiny::reactive({
      d <- dat()
      if (input$f_status != "all") {
        if (input$f_status == "NA_") {
          d <- d[is.na(d$verified), ]
        } else {
          d <- d[!is.na(d$verified) & d$verified == input$f_status, ]
        }
      }
      if (input$f_key != "all")
        d <- d[!is.na(d$citation_key) & d$citation_key == input$f_key, ]
      if (input$f_section != "all")
        d <- d[!is.na(d$section) & d$section == input$f_section, ]
      if (input$hide_done)
        d <- d[is.na(d$verified) | !d$verified %in% c("yes", "corrected"), ]
      d
    })

    # Progress counter in top bar
    output$progress <- shiny::renderText({
      d <- dat()
      n_done  <- sum(d$verified %in% c("yes","no","corrected","context"), na.rm=TRUE)
      n_auto  <- sum(!is.na(d$verified) & d$verified == "auto", na.rm=TRUE)
      n_total <- nrow(d)
      paste0(n_done, " reviewed \u00b7 ", n_auto, " auto \u00b7 ", n_total, " total")
    })

    output$save_msg <- shiny::renderUI({
      if (unsaved()) {
        shiny::span(class = "savemsg", style = "color:#ffcc00;", "Unsaved changes")
      } else if (!is.null(last_save())) {
        shiny::span(class = "savemsg",
          paste("Saved", format(last_save(), "%H:%M:%S")))
      }
    })

    # Table — show truncated text, colour verified
    trunc_chr <- function(x, n = 90) {
      ifelse(!is.na(x) & nchar(x) > n, paste0(substr(x, 1L, n - 3L), "..."), x)
    }

    output$tbl <- DT::renderDT({
      d <- filtered()
      show_cols <- intersect(
        c("section","citation_key","paraphrase","quote","verified","page_or_section","notes"),
        names(d)
      )
      d_show <- d[, show_cols, drop = FALSE]
      d_show$paraphrase <- trunc_chr(d_show$paraphrase)
      d_show$quote      <- trunc_chr(d_show$quote)

      DT::datatable(
        d_show,
        selection = "single",
        rownames  = FALSE,
        options   = list(
          pageLength = 30,
          scrollX    = TRUE,
          dom        = "tip",
          columnDefs = list(
            list(width = "90px",  targets = 0),   # section
            list(width = "170px", targets = 1),   # citation_key
            list(width = "300px", targets = 2),   # paraphrase
            list(width = "300px", targets = 3),   # quote
            list(width = "75px",  targets = 4),   # verified
            list(width = "55px",  targets = 5),   # page_or_section
            list(width = "160px", targets = 6)    # notes
          )
        )
      ) |>
        DT::formatStyle("verified",
          backgroundColor = DT::styleEqual(
            names(status_colours), unname(status_colours)
          )
        )
    }, server = TRUE)

    # Selected row (matched back to full data by sort_index)
    sel_row <- shiny::reactive({
      s <- input$tbl_rows_selected
      if (is.null(s) || length(s) == 0L) return(NULL)
      frow <- filtered()[s, ]
      if (!"sort_index" %in% names(frow)) return(frow)
      dat()[dat()$sort_index == frow$sort_index, ]
    })

    # Detail panel below table
    output$detail <- shiny::renderUI({
      row <- sel_row()
      if (is.null(row) || nrow(row) == 0L) {
        return(shiny::p(style = "color:#999; font-size:12px; padding:4px 0;",
          "Click a row above to review it."))
      }

      quote_content <- if (is.na(row$quote) || row$quote == "") {
        shiny::div(class = "no-quote", "(no quote \u2014 no_match or NA)")
      } else {
        shiny::div(class = "detail-box", row$quote)
      }

      loc <- if (!is.na(row$page_or_section))
        paste0(" \u00b7 p/\u00a7\u00a0", row$page_or_section) else ""

      shiny::tagList(
        shiny::fluidRow(
          shiny::column(6,
            shiny::div(class = "col-lbl", "Paraphrase \u2014 what the report claims"),
            shiny::div(class = "detail-box", row$paraphrase)
          ),
          shiny::column(6,
            shiny::div(class = "col-lbl",
              paste0("Quote from source", loc, " \u2014 ", row$citation_key)),
            quote_content
          )
        ),
        shiny::br(),
        shiny::fluidRow(
          shiny::column(3,
            shiny::selectInput("edit_verified", "Set verified:",
              choices  = c("auto","yes","no","corrected","no_match","context","(NA)" = ""),
              selected = ifelse(is.na(row$verified), "", row$verified),
              width    = "100%")
          ),
          shiny::column(6,
            shiny::textAreaInput("edit_notes", "Notes:",
              value = ifelse(is.na(row$notes) || row$notes == "", "", row$notes),
              rows  = 2, width = "100%",
              placeholder = "Record discrepancy, corrected text, or reason for no/context")
          ),
          shiny::column(3,
            shiny::br(),
            shiny::actionButton("update_row", "Update row",
              class = "btn-primary btn-sm", style = "margin-top:3px;")
          )
        )
      )
    })

    # Apply edit to reactive data
    shiny::observeEvent(input$update_row, {
      row <- sel_row()
      if (is.null(row) || nrow(row) == 0L) return()

      d   <- dat()
      idx <- if ("sort_index" %in% names(d)) {
        which(d$sort_index == row$sort_index)
      } else {
        which(d$citation_key == row$citation_key &
              d$paraphrase   == row$paraphrase)[1L]
      }
      if (length(idx) != 1L) return()

      new_v <- input$edit_verified
      new_n <- input$edit_notes

      d$verified[idx] <- if (is.null(new_v) || new_v == "") NA_character_ else new_v
      d$notes[idx]    <- if (is.null(new_n) || new_n == "") NA_character_ else new_n

      dat(d)
      unsaved(TRUE)
    })

    # Save to CSV
    shiny::observeEvent(input$save_btn, {
      readr::write_excel_csv(dat(), audit_file, na = "")
      unsaved(FALSE)
      last_save(Sys.time())
      message("Saved ", nrow(dat()), " rows to ", audit_file)
    })
  }

  shiny::runApp(shiny::shinyApp(ui, server), launch.browser = launch.browser)
}
