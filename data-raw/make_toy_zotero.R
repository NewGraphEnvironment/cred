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

pdf(pdf_path, width = 8.5, height = 11)
par(mar = c(2, 3, 2, 3), family = "sans")

# Page 1
plot.new()
text(0.5, 0.97, "Smith et al. (2020)", font = 2, cex = 1.1, adj = 0.5)
text(0.5, 0.93, "Habitat Quality Assessment for Chinook Salmon", font = 2, cex = 0.95, adj = 0.5)
text(0.5, 0.88, "Interior British Columbia Streams", cex = 0.9, adj = 0.5)

# Paragraph 1 — spawning gravel / embeddedness
text(0.5, 0.82, "1. Spawning Substrate", font = 2, cex = 0.85, adj = 0.5)
text(0.5, 0.75,
  paste(
    "Spawning substrate embeddedness is the dominant predictor of",
    "egg-to-fry survival for chinook salmon in interior BC streams.",
    "Field surveys at 47 index sites found that reaches where",
    "embeddedness exceeded 25% had egg-to-fry survival rates 62%",
    "lower than adjacent low-embeddedness sites. Fine sediment inputs",
    "from road crossings and livestock access were the primary drivers."
  ),
  cex = 0.78, adj = 0.5
)

# Paragraph 2 — riparian shade and temperature
text(0.5, 0.60, "2. Riparian Shade and Stream Temperature", font = 2, cex = 0.85, adj = 0.5)
text(0.5, 0.53,
  paste(
    "Riparian canopy removal raises maximum summer stream temperatures",
    "by 3 to 7 degrees Celsius in small to medium channels. In reaches",
    "where streamside conifers were harvested within 30 m of the",
    "bankfull channel, daily maximum temperatures increased by an",
    "average of 4.2 degrees C compared to unlogged reference reaches.",
    "Temperature elevations of this magnitude exceed the upper thermal",
    "tolerance of juvenile chinook during late-summer rearing."
  ),
  cex = 0.78, adj = 0.5
)

# Paragraph 3 — road crossings and fish passage
text(0.5, 0.37, "3. Road Crossings and Fish Passage", font = 2, cex = 0.85, adj = 0.5)
text(0.5, 0.28,
  paste(
    "Fish passage assessments at 1,200 road-stream crossings found",
    "that 38 percent were rated as full or partial barriers to adult",
    "chinook migration. Culverts with outlet drops exceeding 15 cm",
    "or insufficient water depth during low flow accounted for 71%",
    "of all barrier crossings. Barrier removal restored upstream",
    "colonisation within 1 to 3 years of installation."
  ),
  cex = 0.78, adj = 0.5
)

# Paragraph 4 — large woody debris (not floodplain — deliberately off-topic
#               so a floodplain paraphrase produces no_match)
text(0.5, 0.12, "4. Large Woody Debris", font = 2, cex = 0.85, adj = 0.5)
text(0.5, 0.05,
  paste(
    "Juvenile chinook density in pool habitat was positively correlated",
    "with large woody debris loading. Sites with more than 25 pieces of",
    "wood per 100 m of channel had 2.8 times higher juvenile density",
    "than sites with fewer than 5 pieces per 100 m."
  ),
  cex = 0.78, adj = 0.5
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

# Link items to fields
dbExecute(con, "INSERT INTO itemData VALUES (1, 1, 1)")
dbExecute(con, "INSERT INTO itemData VALUES (2, 1, 2)")
dbExecute(con, "INSERT INTO itemData VALUES (3, 1, 3)")
dbExecute(con, "INSERT INTO itemData VALUES (1, 2, 4)")
dbExecute(con, "INSERT INTO itemData VALUES (2, 2, 5)")
dbExecute(con, "INSERT INTO itemData VALUES (3, 2, 6)")

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
