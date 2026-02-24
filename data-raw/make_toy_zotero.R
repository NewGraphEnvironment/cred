# data-raw/make_toy_zotero.R
#
# Build the toy Zotero SQLite database and sample source files stored in
# inst/extdata/. Run this script once to regenerate the toy data if the
# schema or content needs updating.
#
# Usage:
#   Rscript data-raw/make_toy_zotero.R
#   # or from R:
#   source("data-raw/make_toy_zotero.R")

library(RSQLite)
library(officer)

extdata <- "inst/extdata"
storage <- file.path(extdata, "storage")

# ---------------------------------------------------------------------------
# 1. Toy PDF: salmon_habitat.pdf  (item key TOYPDF1)
# ---------------------------------------------------------------------------
pdf_path <- file.path(storage, "TOYPDF1", "salmon_habitat.pdf")

pdf(pdf_path, width = 8.5, height = 11)
par(mar = c(2, 2, 2, 2))
plot.new()
text(0.5, 0.95, "Smith et al. (2020) — Salmon Habitat Quality", font = 2, cex = 1.2)
text(0.5, 0.85,
  paste(
    "Spawning gravel embeddedness is the primary metric used to assess",
    "habitat quality for chinook salmon in interior British Columbia.",
    "Sites with embeddedness below 25% support significantly higher",
    "egg-to-fry survival than heavily embedded substrates (>50%)."
  ),
  cex = 0.8, adj = 0.5
)
text(0.5, 0.70,
  paste(
    "Riparian vegetation provides critical shade that moderates summer",
    "stream temperatures. Removal of streamside conifers raises maximum",
    "daily temperatures by 3-7 degrees Celsius in small channels,",
    "directly impairing juvenile salmonid growth and survival."
  ),
  cex = 0.8, adj = 0.5
)
text(0.5, 0.55,
  paste(
    "Road crossings with undersized culverts represent the most",
    "pervasive barrier to salmon passage in the study watershed.",
    "Of 1,200 assessed crossings, 38% were rated as full or partial",
    "barriers to adult chinook migration."
  ),
  cex = 0.8, adj = 0.5
)
dev.off()

message("Created: ", pdf_path)

# ---------------------------------------------------------------------------
# 2. Toy docx: beaver_ecology.docx  (item key TOYDOC1)
# ---------------------------------------------------------------------------
docx_path <- file.path(storage, "TOYDOC1", "beaver_ecology.docx")

doc <- read_docx()
doc <- body_add_par(doc, "Jones (2019) — Beaver Ecology and Salmonid Habitat",
                    style = "heading 1")
doc <- body_add_par(doc,
  paste(
    "Beaver dams increase overwinter survival of juvenile salmonids by",
    "creating slow-water refuges with stable thermal conditions.",
    "Pond habitats behind dams support densities 3-5 times higher than",
    "adjacent free-flowing reaches during winter low-flow periods."
  ),
  style = "Normal"
)
doc <- body_add_par(doc,
  paste(
    "Reintroduction of beavers to degraded streams has been shown to",
    "reduce peak flows by 30% and extend summer baseflows by up to",
    "six weeks compared to pre-reintroduction conditions."
  ),
  style = "Normal"
)
doc <- body_add_par(doc,
  paste(
    "The keystone role of beavers in Pacific salmon freshwater habitat",
    "is well established. Removal through trapping reduced pond habitat",
    "extent by an estimated 60% across the study watershed between",
    "1850 and 1950."
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

# Minimal Zotero schema (only tables queried by crd_zot_src_lookup)
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

# Fields
dbExecute(con, "INSERT INTO fields VALUES (1, 'citationKey')")
dbExecute(con, "INSERT INTO fields VALUES (2, 'title')")

# Parent items
# itemID 1: smith2020SalmonHabitat (PDF attached)
# itemID 2: jones2019BeaverEcology (docx attached)
# itemID 3: doe2021NoFile           (no attachment — metadata only)
dbExecute(con, "INSERT INTO items VALUES (1, 14, 1, 'PARENT001')")
dbExecute(con, "INSERT INTO items VALUES (2, 14, 1, 'PARENT002')")
dbExecute(con, "INSERT INTO items VALUES (3, 14, 1, 'PARENT003')")

# Attachment items (the actual file nodes — key = storage directory name)
dbExecute(con, "INSERT INTO items VALUES (10, 3, 1, 'TOYPDF1')")
dbExecute(con, "INSERT INTO items VALUES (20, 3, 1, 'TOYDOC1')")

# Citation keys as itemData
# valueID 1-3: citationKey values; 4-6: title values
dbExecute(con, "INSERT INTO itemDataValues VALUES (1, 'smith2020SalmonHabitat')")
dbExecute(con, "INSERT INTO itemDataValues VALUES (2, 'jones2019BeaverEcology')")
dbExecute(con, "INSERT INTO itemDataValues VALUES (3, 'doe2021NoFile')")
dbExecute(con, "INSERT INTO itemDataValues VALUES (4, 'Salmon Habitat Quality in Interior BC')")
dbExecute(con, "INSERT INTO itemDataValues VALUES (5, 'Beaver Ecology and Salmonid Habitat')")
dbExecute(con, "INSERT INTO itemDataValues VALUES (6, 'Stream Temperature and Salmon Distribution')")

# itemData rows linking items to their citationKey and title
dbExecute(con, "INSERT INTO itemData VALUES (1, 1, 1)")  # item1 citationKey=smith2020
dbExecute(con, "INSERT INTO itemData VALUES (2, 1, 2)")  # item2 citationKey=jones2019
dbExecute(con, "INSERT INTO itemData VALUES (3, 1, 3)")  # item3 citationKey=doe2021
dbExecute(con, "INSERT INTO itemData VALUES (1, 2, 4)")  # item1 title
dbExecute(con, "INSERT INTO itemData VALUES (2, 2, 5)")  # item2 title
dbExecute(con, "INSERT INTO itemData VALUES (3, 2, 6)")  # item3 title

# Attachments
dbExecute(con, "INSERT INTO itemAttachments VALUES (
  10, 1, 'storage:salmon_habitat.pdf', 'application/pdf'
)")
dbExecute(con, "INSERT INTO itemAttachments VALUES (
  20, 2,
  'storage:beaver_ecology.docx',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
)")
# item 3 (doe2021NoFile) has no attachment row — simulates metadata-only entry

dbDisconnect(con)
message("Created: ", db_path)
message("\nToy data ready in inst/extdata/")
