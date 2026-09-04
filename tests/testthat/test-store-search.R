# Regression tests for #27 — crd_search() against ragnar's list columns.
#
# The fixture is a real ragnar store retrieved through the real hybrid path
# (see helper-store.R). A hand-built frame with atomic columns is what would let
# this recur, so the integration tests construct nothing by hand; the unit tests
# below them test the reducer itself and say so.

test_that("the fixture reaches the failure: hybrid retrieval yields multi-element cells", {
  # The premise the regression test rests on. Two separate things have to be
  # true, and only the second is the one that throws — a list column of
  # length-1 cells coerces perfectly well.
  store <- local_ragnar_store()
  res <- ragnar::ragnar_retrieve(store, .crd_test_query(), top_k = .crd_test_top_k())

  list_cols <- names(res)[vapply(res, is.list, logical(1))]
  expect_true(length(intersect(c("bm25", "cosine_distance"), list_cols)) > 0L)
  expect_false("metric_value" %in% names(res))

  # ragnar merges adjacent retrieved chunks into one row (deoverlap = TRUE), and
  # that merge is what puts more than one value in a cell. If a future ragnar
  # stops merging, this fails HERE naming the real cause rather than letting the
  # behaviour tests below pass for the wrong reason.
  expect_gt(max(lengths(res$bm25)), 1L)

  # And the untouched frame really does still throw the reported error, so the
  # tests below are not asserting against a bug that has gone away upstream.
  expect_error(as.numeric(res$bm25), "cannot be coerced")
})

test_that("crd_search() returns atomic columns from a hybrid-retrieved store", {
  store <- local_ragnar_store()

  # Before the fix this errors: 'list' object cannot be coerced to type 'double'
  out <- crd_search(store, .crd_test_query(), top_k = .crd_test_top_k())

  expect_s3_class(out, "tbl_df")
  expect_gt(nrow(out), 0L)

  # Real coverage: these three are the list columns.
  expect_type(out$score, "double")
  expect_type(out$chunk_id, "integer")
  expect_type(out$metric, "character")

  # NOT coverage, and worth saying so rather than letting a green suite imply
  # otherwise. `chunks_deoverlap()` list-ifies with
  # `across(-c(start, end, context, text), \(x) list(unlist(x)))` and groups by
  # `origin`, so start/end/origin/text are atomic before crd_search() ever sees
  # them. These assertions pass identically whether the `.crd_flat()` calls on
  # those four columns exist or are reverted to bare coercion — they are
  # deliberate defence against a shape ragnar does not currently produce
  # (and, for `origin`, against `.crd_zot_key_from_path()` calling `dirname()`
  # on a list, which errors), not something this test can guard.
  expect_type(out$start, "integer")
  expect_type(out$end, "integer")
  expect_type(out$origin, "character")
  expect_type(out$text, "character")

  expect_false(any(vapply(out, is.list, logical(1))))

  # Scores are real values, not an all-NA column left by a coercion that gave up.
  expect_true(any(!is.na(out$score)))
  expect_true(all(out$metric[!is.na(out$score)] %in% c("bm25", "cosine_distance")))

  # Confirms the hybrid path ran; a BM25 fallback returns atomic columns and
  # could not have exercised the fix.
  expect_identical(unique(out$method), "hybrid")
})

test_that("a merged row is scored by its best constituent chunk, per metric direction", {
  # The heart of #27. A deoverlapped row represents several chunks, so its
  # score must be the best one among them — higher is better for bm25, lower is
  # better for cosine_distance. Taking the first would score some rows on a
  # constituent that never matched, and would attribute the wrong metric where
  # the leading chunk's bm25 is NA and a later one's is not.
  store <- local_ragnar_store()
  res <- ragnar::ragnar_retrieve(store, .crd_test_query(), top_k = .crd_test_top_k())
  out <- crd_search(store, .crd_test_query(), top_k = .crd_test_top_k())

  # `res` and `out` are two independent round-trips to duckdb, and every
  # assertion below indexes both by the same `i`. Equal row counts do not make
  # them row-aligned; this does.
  expect_identical(nrow(out), nrow(res))
  expect_identical(out$text, res$text)

  multi <- which(lengths(res$bm25) > 1L)
  expect_gt(length(multi), 0L)   # premise: there IS a merged row to check

  for (i in multi) {
    b <- suppressWarnings(as.numeric(unlist(res$bm25[[i]])))
    cd <- suppressWarnings(as.numeric(unlist(res$cosine_distance[[i]])))
    if (any(!is.na(b))) {
      expect_identical(out$metric[i], "bm25")
      expect_equal(out$score[i], max(b, na.rm = TRUE))
    } else if (any(!is.na(cd))) {
      # Reached, but NOT discriminating. Measured across queries and every
      # top_k from 3 to 20: no row reaching this branch has
      # `first(cosine) != min(cosine)`, because a merged row whose constituents
      # differ in distance essentially always carries a bm25 score too and is
      # claimed by the branch above. Rows retrieved only by VSS *within* hybrid
      # do reach here, but with their constituents already in ascending order.
      # So a min -> first regression on cosine_distance would pass this test.
      # The unit test ".crd_retrieval_score prefers the lowest distance within a
      # merged row" below is the ONLY guard on that direction.
      expect_identical(out$metric[i], "cosine_distance")
      expect_equal(out$score[i], min(cd, na.rm = TRUE))
    }
    # chunk_id is the passage's opening chunk, matching ragnar's own
    # `start = first(start)`.
    expect_identical(out$chunk_id[i], as.integer(unlist(res$chunk_id[[i]])[1]))
  }
})

test_that("crd_search() still works on the bm25 path, which returns atomic columns", {
  # A control. BM25-only retrieval never produces list columns, so this passing
  # proves nothing about #27 — it is here so that a fix which breaks the
  # long-form `metric_value` branch is caught.
  store <- local_ragnar_store()
  out <- crd_search(store, .crd_test_query(), top_k = 3L, method = "bm25")

  expect_type(out$score, "double")
  expect_true(any(!is.na(out$score)))
  expect_identical(unique(out$metric), "bm25")
  expect_identical(unique(out$method), "bm25")
})

# --- .crd_flat, tested directly -------------------------------------------
# These build frames by hand, which is exactly what cannot substitute for the
# integration tests above. They pin the reducer's edge cases, nothing more.

test_that(".crd_flat reduces list columns to atomic vectors of the requested type", {
  expect_identical(.crd_flat(list(1.5, 2.5), "numeric"), c(1.5, 2.5))
  expect_identical(.crd_flat(list(1L, 2L), "integer"), c(1L, 2L))
  expect_identical(.crd_flat(list("a", "b"), "character"), c("a", "b"))
})

test_that(".crd_flat reduces a multi-element cell by the requested direction", {
  x <- list(c(1.5, 9.9), 2.5)
  expect_identical(.crd_flat(x, "numeric", "max"), c(9.9, 2.5))
  expect_identical(.crd_flat(x, "numeric", "min"), c(1.5, 2.5))
  expect_identical(.crd_flat(x, "numeric", "first"), c(1.5, 2.5))
})

test_that(".crd_flat ignores NA constituents, which is how ragnar marks a metric miss", {
  # The case that makes 'first' wrong: the leading chunk was not retrieved by
  # this metric, but a later one was, and that row does have a real score.
  expect_identical(.crd_flat(list(c(NA, 1.26)), "numeric", "max"), 1.26)
  expect_identical(.crd_flat(list(c(NA, 1.26)), "numeric", "first"), 1.26)

  # All-NA must stay NA and must not become -Inf from max(numeric(0)).
  expect_identical(.crd_flat(list(c(NA_real_, NA_real_)), "numeric", "max"), NA_real_)
  expect_silent(.crd_flat(list(NA_real_), "numeric", "max"))
})

test_that(".crd_flat maps an empty cell to a typed NA rather than dropping the row", {
  # Dropping would shorten the column and silently misalign every other column
  # in the tibble. The NA must carry the column's type, or unlist() demotes it.
  expect_identical(.crd_flat(list(1.5, numeric(0), 2.5), "numeric"), c(1.5, NA, 2.5))
  expect_identical(.crd_flat(list(NULL, 3L), "integer"), c(NA_integer_, 3L))
  expect_identical(.crd_flat(list(NULL, "a"), "character"), c(NA_character_, "a"))
})

test_that(".crd_flat warns identically on both branches when coercion loses data", {
  # The atomic and list branches must agree. Feeding input that structurally
  # cannot warn (numeric -> numeric) asserts nothing: it passes for an
  # implementation that suppresses warnings and for one that does not. A score
  # column holding non-numeric data yields an all-NA `score`, which is the
  # silent failure this whole function exists to end, so the warning has to
  # survive.
  expect_warning(a <- .crd_flat(c("a", "b"), "numeric"), "NAs introduced")
  expect_warning(l <- .crd_flat(list("a", "b"), "numeric"), "NAs introduced")
  expect_identical(a, c(NA_real_, NA_real_))
  expect_identical(l, c(NA_real_, NA_real_))
})

test_that(".crd_flat passes atomic input through unchanged", {
  # The common case: every column on the bm25 path arrives atomic.
  expect_silent(got <- .crd_flat(c(1.5, 2.5), "numeric", "max"))
  expect_identical(got, c(1.5, 2.5))
  expect_identical(.crd_flat(c(1L, 2L), "integer"), c(1L, 2L))
  expect_identical(.crd_flat(c("a", NA), "character"), c("a", NA))

  # A merged row is ragnar's ordinary output, not an anomaly, so reducing one
  # must be silent — a warning here would fire on most real searches. This one
  # can fail: an implementation that warned on multi-element cells (the contract
  # first proposed for #27) would trip it.
  expect_silent(.crd_flat(list(c(1, 2), c(3, 4)), "numeric", "max"))
})

test_that(".crd_flat handles a missing column and a zero-row frame", {
  expect_identical(.crd_flat(NULL, "numeric"), numeric(0))
  expect_identical(.crd_flat(list(), "integer"), integer(0))
  expect_identical(.crd_flat(character(0), "character"), character(0))
})

test_that(".crd_retrieval_score handles the hybrid shape without coercing a list", {
  # The reported crash, isolated: `metric_value` absent, both score columns
  # lists, one row merged from two chunks.
  res <- data.frame(text = c("a", "b", "c"), stringsAsFactors = FALSE)
  res$cosine_distance <- list(c(0.30, 0.10), 0.2, 0.3)
  res$bm25 <- list(c(NA_real_, 1.26), NA_real_, NA_real_)

  got <- .crd_retrieval_score(res)

  expect_type(got$score, "double")
  expect_length(got$score, 3L)
  # Row 1: bm25 present on the second constituent only — best is 1.26, and the
  # metric is bm25, not the cosine_distance a first-element reduction would give.
  expect_identical(got$score, c(1.26, 0.2, 0.3))
  expect_identical(got$metric, c("bm25", "cosine_distance", "cosine_distance"))
})

test_that(".crd_retrieval_score prefers the lowest distance within a merged row", {
  # THE ONLY GUARD on the cosine_distance `min` direction — see the note in the
  # merged-row integration test above for why no real retrieval frame from this
  # fixture can discriminate min from first. Hand-built for exactly that reason,
  # which is a compromise, not a preference: do not delete it as a redundant
  # edge case.
  res <- data.frame(text = "a", stringsAsFactors = FALSE)
  res$cosine_distance <- list(c(0.30, 0.10))
  got <- .crd_retrieval_score(res)
  expect_identical(got$score, 0.10)
  expect_identical(got$metric, "cosine_distance")
})

test_that(".crd_retrieval_score still reads the long-form metric_value shape", {
  res <- data.frame(metric_name = c("bm25", "bm25"), metric_value = c(1.2, 0.8),
                    stringsAsFactors = FALSE)
  got <- .crd_retrieval_score(res)
  expect_identical(got$score, c(1.2, 0.8))
  expect_identical(got$metric, c("bm25", "bm25"))
})

test_that(".crd_retrieval_score reduces long-form metric_value in its own direction", {
  # `method = "vss"` reports metric_name = "cosine_distance", where LOWER is
  # better. A fixed "max" here would return the worst constituent — silently,
  # with the right type. Unreachable through ragnar today (neither
  # ragnar_retrieve_bm25() nor _vss() takes `deoverlap`, so metric_value arrives
  # atomic), so this is the only thing standing between the direction and a
  # future upstream change.
  res <- data.frame(metric_name = c("cosine_distance", "cosine_distance"),
                    stringsAsFactors = FALSE)
  res$metric_value <- list(c(0.30, 0.10), 0.5)
  got <- .crd_retrieval_score(res)
  expect_identical(got$score, c(0.10, 0.5))

  res$metric_name <- c("bm25", "bm25")
  expect_identical(.crd_retrieval_score(res)$score, c(0.30, 0.5))
})

test_that(".crd_metric_direction defaults to min for an unrecognised metric", {
  # "min", not "max". `ragnar:::method_to_info()` maps every alternative it
  # offers -- cosine_distance, euclidean_distance, negative_inner_product -- to
  # "ASC", so BM25 is the lone higher-is-better metric and an unknown name is
  # likelier to be another distance. The intuitive default is the wrong one.
  expect_identical(.crd_metric_direction("bm25"), "max")
  expect_identical(.crd_metric_direction("cosine_distance"), "min")
  expect_identical(.crd_metric_direction("euclidean_distance"), "min")
  expect_identical(.crd_metric_direction("negative_inner_product"), "min")
  expect_identical(.crd_metric_direction("some_future_metric"), "min")
  expect_identical(.crd_metric_direction(NA_character_), "min")
})

test_that("both retrieval shapes score an unrecognised metric the same way", {
  # The mechanism behind two earlier defects: the table was authoritative about
  # direction but each branch decided metric MEMBERSHIP its own way, so the same
  # column got two different wrong answers -- pivoted dropped it to all-NA,
  # long-form scored it in the wrong direction.
  wide <- data.frame(text = c("a", "b"), stringsAsFactors = FALSE)
  wide$euclidean_distance <- list(c(0.9, 0.2), 0.5)
  long <- data.frame(metric_name = c("euclidean_distance", "euclidean_distance"),
                     stringsAsFactors = FALSE)
  long$metric_value <- list(c(0.9, 0.2), 0.5)

  expect_identical(.crd_retrieval_score(wide)$score,
                   .crd_retrieval_score(long)$score)
  expect_identical(.crd_retrieval_score(wide)$score, c(0.2, 0.5))
  expect_identical(.crd_retrieval_score(wide)$metric,
                   c("euclidean_distance", "euclidean_distance"))
})

test_that(".crd_retrieval_score scores long-form rows whose metric_name is missing", {
  # Regression guard. Grouping the score loop by metric made an absent or NA
  # `metric_name` skip the loop body entirely, returning an all-NA score while
  # `metric_value` sat right there -- the exact silent failure this function
  # exists to end, reintroduced on a different shape by the fix for the first.
  expect_identical(
    .crd_retrieval_score(data.frame(metric_value = c(1.2, 0.8)))$score,
    c(1.2, 0.8)
  )
  got <- .crd_retrieval_score(
    data.frame(metric_name = c("bm25", NA), metric_value = c(1.2, 0.8),
               stringsAsFactors = FALSE)
  )
  expect_identical(got$score, c(1.2, 0.8))
})

test_that("a non-score column is never mistaken for a metric", {
  # `.crd_non_metric_cols` cannot be assumed complete, so the type guard is what
  # actually protects this: a character column added upstream must not become a
  # score however unfamiliar its name.
  res <- data.frame(text = c("a", "b"), some_new_label = c("x", "y"),
                    stringsAsFactors = FALSE)
  res$bm25 <- list(1.5, 2.5)
  got <- .crd_retrieval_score(res)
  expect_identical(got$score, c(1.5, 2.5))
  expect_identical(got$metric, c("bm25", "bm25"))
})

test_that(".crd_flat keeps values on their own rows regardless of empty cells", {
  # `.crd_flat` reduces by splitting a once-coerced vector into per-cell groups.
  # An empty cell contributes no entries, so its group is simply absent from the
  # split — and the lookup is by NAME rather than position precisely so that a
  # missing group yields NA on that row instead of shifting every later value up
  # one. Silent misalignment of a whole column is the worst outcome this
  # function has available to it, so it is pinned rather than reasoned about.
  expect_identical(.crd_flat(list(numeric(0), 5, 7), "numeric", "max"), c(NA, 5, 7))
  expect_identical(.crd_flat(list(5, numeric(0), 7), "numeric", "max"), c(5, NA, 7))
  expect_identical(.crd_flat(list(5, 7, numeric(0)), "numeric", "max"), c(5, 7, NA))
  expect_identical(.crd_flat(list(NULL, 5, NULL, 7), "numeric", "max"), c(NA, 5, NA, 7))
})

test_that(".crd_flat does not misalign at the lengths a real search returns", {
  # An earlier version of this test claimed split() names sort lexically, "10"
  # before "2". They do not: the grouping vector is an integer factor, whose
  # levels sort numerically. So with no gaps, positional and name-based lookup
  # coincide, and the first assertion below CANNOT discriminate — it is here as
  # a plain identity check, not as a guard.
  #
  # The gap is what discriminates, and it is worth repeating at a two-digit
  # length because that is the shape a real search returns: hybrid retrieval at
  # top_k = 10 routinely yields more than nine rows, so an off-by-one in the
  # lookup would corrupt ordinary results rather than an edge case.
  expect_identical(.crd_flat(as.list(as.numeric(1:12)), "numeric", "max"),
                   as.numeric(1:12))

  gap <- c(as.list(as.numeric(1:9)), list(numeric(0)), list(11), list(12))
  expect_identical(.crd_flat(gap, "numeric", "max"), c(1:9, NA, 11, 12))

  both <- c(as.list(as.numeric(1:8)), list(numeric(0)), list(c(100, 200)),
            list(11), list(c(5, 300)))
  expect_identical(.crd_flat(both, "numeric", "max"), c(1:8, NA, 200, 11, 300))
})
