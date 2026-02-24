# data-raw/make_toy_zotero.R
#
# Build the toy Zotero SQLite database and sample source files stored in
# inst/extdata/. Run this script once to regenerate the toy data if the
# schema or content needs updating.
#
# Usage:
#   Rscript data-raw/make_toy_zotero.R

library(RSQLite)
library(officer)

extdata <- "inst/extdata"
storage <- file.path(extdata, "storage")

# ---------------------------------------------------------------------------
# 1. Toy PDF: salmon_habitat.pdf  (item key TOYPDF1)
#    Designed to match three realistic paraphrases and produce no_match
#    for one (a floodplain claim not covered in this paper).
# ---------------------------------------------------------------------------
pdf_path <- file.path(storage, "TOYPDF1", "salmon_habitat.pdf")

# Each paragraph goes on its own page so pdftools extracts clean, unambiguous
# page-level text. Putting multiple paragraphs on one page causes pdftools to
# return truncated, left-clipped fragments from R's pdf() positioning engine.
.page <- function(heading, body) {
  plot.new()
  text(0.5, 0.95, heading, font = 2, cex = 0.9, adj = 0.5)
  text(0.05, 0.80, body, cex = 0.8, adj = c(0, 1))
}

pdf(pdf_path, width = 8.5, height = 11)
par(mar = c(1, 1, 1, 1), family = "sans")

# Cover page
plot.new()
text(0.5, 0.6, "Smith et al. (2020)", font = 2, cex = 1.2, adj = 0.5)
text(0.5, 0.52, "Habitat Quality Assessment for Chinook Salmon", cex = 1.0, adj = 0.5)
text(0.5, 0.45, "Interior British Columbia Streams", cex = 0.9, adj = 0.5)

# Page 2 — spawning gravel / embeddedness
.page("1. Spawning Substrate",
  paste0(
    "Spawning substrate embeddedness is the dominant predictor of egg-to-fry survival\n",
    "for chinook salmon in interior BC streams. Field surveys at 47 index sites found\n",
    "that reaches where embeddedness exceeded 25% had egg-to-fry survival rates 62%\n",
    "lower than adjacent low-embeddedness sites. Fine sediment inputs from road\n",
    "crossings and livestock access were the primary drivers."
  )
)

# Page 3 — riparian shade and temperature
.page("2. Riparian Shade and Stream Temperature",
  paste0(
    "Riparian canopy removal raises maximum summer stream temperatures by 3 to 7\n",
    "degrees Celsius in small to medium channels. In reaches where streamside conifers\n",
    "were harvested within 30 m of the bankfull channel, daily maximum temperatures\n",
    "increased by an average of 4.2 degrees C compared to unlogged reference reaches.\n",
    "Temperature elevations of this magnitude exceed the upper thermal tolerance of\n",
    "juvenile chinook during late-summer rearing."
  )
)

# Page 4 — road crossings and fish passage
.page("3. Road Crossings and Fish Passage",
  paste0(
    "Fish passage assessments at 1,200 road-stream crossings found that 38 percent\n",
    "were rated as full or partial barriers to adult chinook migration. Culverts with\n",
    "outlet drops exceeding 15 cm or insufficient water depth during low flow accounted\n",
    "for 71% of all barrier crossings. Barrier removal restored upstream colonisation\n",
    "within 1 to 3 years of installation."
  )
)

# Page 5 — large woody debris (deliberately off-topic: no floodplain content,
#           so a floodplain paraphrase scores below threshold → no_match)
.page("4. Large Woody Debris",
  paste0(
    "Pool density and large woody debris loading were positively correlated across\n",
    "all 47 assessment reaches. Sites with more than 25 pieces of wood per 100 m of\n",
    "channel had 2.8 times more pool-associated fish than reaches with fewer than\n",
    "5 pieces per 100 m. Wood recruitment from adjacent riparian conifers was the\n",
    "primary driver of debris loading."
  )
)

dev.off()
message("Created: ", pdf_path)

# ---------------------------------------------------------------------------
# 2. Toy docx: beaver_ecology.docx  (item key TOYDOC1)
#    Four paragraphs covering: overwinter survival, peak flows, historical
#    removal, and floodplain side-channel growth.
# ---------------------------------------------------------------------------
docx_path <- file.path(storage, "TOYDOC1", "beaver_ecology.docx")

doc <- read_docx()
doc <- body_add_par(doc,
  "Jones (2019) — Beaver Ecology and Salmonid Habitat Restoration",
  style = "heading 1"
)
doc <- body_add_par(doc,
  paste(
    "Beaver dams significantly increase overwinter survival of juvenile",
    "salmonids by creating ponded habitat with stable thermal regimes and",
    "reduced flow velocities. Electrofishing surveys recorded juvenile",
    "steelhead and coho salmon densities 3.4 times higher in beaver pond",
    "habitat than in adjacent free-flowing channel reaches. The slow-water",
    "refuges created by beaver dams provide shelter from winter spates while",
    "maintaining access to benthic invertebrate prey."
  ),
  style = "Normal"
)
doc <- body_add_par(doc,
  paste(
    "Experimental reintroduction of beavers to an incised stream reach reduced",
    "peak daily flows by 31 percent during late-season storm events compared to",
    "an upstream reference reach without beavers. Summer baseflow duration",
    "extended by five weeks in the beaver-colonised section due to increased",
    "groundwater storage in pond sediments."
  ),
  style = "Normal"
)
doc <- body_add_par(doc,
  paste(
    "Archival trapping records and aerial photograph analysis indicate that",
    "beaver pond habitat extent declined by approximately 60 percent between",
    "1850 and 1950 across the study watershed, primarily due to commercial",
    "trapping pressure. This loss of ponded water reduced overwinter rearing",
    "capacity and likely contributed to declining winter survival of juvenile",
    "salmonids during the late 19th and early 20th centuries."
  ),
  style = "Normal"
)
doc <- body_add_par(doc,
  paste(
    "Floodplain connectivity is restored in years when peak flows exceed",
    "bankfull discharge. Juvenile chinook tagged in the main channel were",
    "detected in floodplain side channels during three consecutive high-flow",
    "events, where they remained for 12 to 34 days and achieved growth rates",
    "40 percent higher than fish remaining in the mainstem."
  ),
  style = "Normal"
)
print(doc, target = docx_path)
message("Created: ", docx_path)

# ---------------------------------------------------------------------------
# 3. Toy Zotero SQLite database
# ---------------------------------------------------------------------------
db_path <- file.path(extdata, "zotero.sqlite")
if (file.exists(db_path)) unlink(db_path)

con <- dbConnect(SQLite(), db_path)

dbExecute(con, "CREATE TABLE items (
  itemID    INTEGER PRIMARY KEY,
  itemTypeID INTEGER,
  libraryID INTEGER,
  key       TEXT NOT NULL
)")
dbExecute(con, "CREATE TABLE fields (
  fieldID   INTEGER PRIMARY KEY,
  fieldName TEXT NOT NULL
)")
dbExecute(con, "CREATE TABLE itemData (
  itemID   INTEGER,
  fieldID  INTEGER,
  valueID  INTEGER
)")
dbExecute(con, "CREATE TABLE itemDataValues (
  valueID INTEGER PRIMARY KEY,
  value   TEXT NOT NULL
)")
dbExecute(con, "CREATE TABLE itemAttachments (
  itemID        INTEGER PRIMARY KEY,
  parentItemID  INTEGER,
  path          TEXT,
  contentType   TEXT
)")

dbExecute(con, "INSERT INTO fields VALUES (1, 'citationKey')")
dbExecute(con, "INSERT INTO fields VALUES (2, 'title')")
dbExecute(con, "INSERT INTO fields VALUES (3, 'abstractNote')")

# Parent items
dbExecute(con, "INSERT INTO items VALUES (1, 14, 1, 'PARENT001')")  # smith2020
dbExecute(con, "INSERT INTO items VALUES (2, 14, 1, 'PARENT002')")  # jones2019
dbExecute(con, "INSERT INTO items VALUES (3, 14, 1, 'PARENT003')")  # doe2021 (no attachment)

# Attachment items (key = storage subdirectory name)
dbExecute(con, "INSERT INTO items VALUES (10, 3, 1, 'TOYPDF1')")
dbExecute(con, "INSERT INTO items VALUES (20, 3, 1, 'TOYDOC1')")

# Citation key values
dbExecute(con, "INSERT INTO itemDataValues VALUES (1, 'smith2020SalmonHabitat')")
dbExecute(con, "INSERT INTO itemDataValues VALUES (2, 'jones2019BeaverEcology')")
dbExecute(con, "INSERT INTO itemDataValues VALUES (3, 'doe2021NoFile')")
dbExecute(con, "INSERT INTO itemDataValues VALUES (4, 'Habitat Quality Assessment for Chinook Salmon')")
dbExecute(con, "INSERT INTO itemDataValues VALUES (5, 'Beaver Ecology and Salmonid Habitat Restoration')")
dbExecute(con, "INSERT INTO itemDataValues VALUES (6, 'Stream Temperature and Salmon Distribution')")

# Abstract values (fieldID 3 = abstractNote)
# doe2021 abstract deliberately contains the tokens in the vignette/test NA paraphrase
# so abstract matching moves that row from NA to abstract_match
dbExecute(con, "INSERT INTO itemDataValues VALUES (7, 'Assessment of habitat quality limiting factors for chinook salmon in interior BC streams. Examines spawning substrate embeddedness, riparian shade and stream temperature, road crossing fish passage barriers, and large woody debris loading across 47 index sites.')")
dbExecute(con, "INSERT INTO itemDataValues VALUES (8, 'Beaver reintroduction as a salmonid habitat restoration strategy. Documents effects on overwinter juvenile survival, peak flow attenuation, baseflow extension, and floodplain side-channel connectivity for chinook and other salmonids.')")
dbExecute(con, "INSERT INTO itemDataValues VALUES (9, 'Stream temperature governs the spatial distribution of salmonid populations across Pacific Northwest watersheds. During summer low flows, elevated temperatures limits accessible rearing area for juvenile chinook and other salmonids, constraining population productivity in thermally marginal streams.')")

# Link items to fields
dbExecute(con, "INSERT INTO itemData VALUES (1, 1, 1)")
dbExecute(con, "INSERT INTO itemData VALUES (2, 1, 2)")
dbExecute(con, "INSERT INTO itemData VALUES (3, 1, 3)")
dbExecute(con, "INSERT INTO itemData VALUES (1, 2, 4)")
dbExecute(con, "INSERT INTO itemData VALUES (2, 2, 5)")
dbExecute(con, "INSERT INTO itemData VALUES (3, 2, 6)")
dbExecute(con, "INSERT INTO itemData VALUES (1, 3, 7)")  # smith2020 abstract
dbExecute(con, "INSERT INTO itemData VALUES (2, 3, 8)")  # jones2019 abstract
dbExecute(con, "INSERT INTO itemData VALUES (3, 3, 9)")  # doe2021 abstract

# Attachments (item 3 has none — simulates metadata-only entry)
dbExecute(con, "INSERT INTO itemAttachments VALUES (
  10, 1, 'storage:salmon_habitat.pdf', 'application/pdf'
)")
dbExecute(con, "INSERT INTO itemAttachments VALUES (
  20, 2, 'storage:beaver_ecology.docx',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
)")

dbDisconnect(con)
message("Created: ", db_path)
message("\nToy data ready in inst/extdata/")
