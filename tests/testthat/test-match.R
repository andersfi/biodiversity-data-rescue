# R/match.R: coordinates, station-years, score, band, Wilson interval, metrics.
# Synthetic inputs only; no repository data.

CFG <- list(station_radius_m = 300, name_only_factor = 0.5, min_token_chars = 4, name_stopwords = c("bekk", "nedre"),
            weights = list(place_time = 4, institution = 1, dataset_name = 1, direct_link = 3),
            bands = list(in_gbif_min_score = 0.5, not_in_gbif_max_score = 0.1,
                         not_in_gbif_max_coverage = 0, not_in_gbif_min_located = 0.8))
SCOPE <- list(region = list(label = "Testby kommune",
                            excluded_neighbours = list(list(gadm_gid = "X", label = "Nabo"))))

test_that("utm_to_lonlat gives the central meridian and a known northing", {
  ll <- utm_to_lonlat(500000, 0, zone = 32)
  expect_equal(ll$lon, 9, tolerance = 1e-9)
  expect_equal(ll$lat, 0, tolerance = 1e-9)
  # 60° N on the central meridian of a UTM zone: northing 6 651 411.19 m (GRS80).
  ll <- utm_to_lonlat(500000, 6651411.19, zone = 32)
  expect_equal(ll$lat, 60, tolerance = 1e-6)
  # 1 km of easting at 63.4° N: the spherical haversine underestimates east-west
  # distances there by ~0.35 % (prime-vertical radius > mean radius); fine at 300 m.
  ll2 <- utm_to_lonlat(c(569000, 570000), c(7032000, 7032000), zone = 32)
  expect_equal(haversine_m(ll2$lon[1], ll2$lat[1], ll2$lon[2], ll2$lat[2]), 1000, tolerance = 0.005)
})

test_that("haversine_m is zero for the same point and ~111 km per degree latitude", {
  expect_equal(haversine_m(10, 63, 10, 63), 0)
  expect_equal(haversine_m(10, 63, 10, 64), 111195, tolerance = 1e-3)
})

test_that("name_tokens drops short words, numbers and stop words", {
  expect_equal(name_tokens("Sagelva (nedre) 1978, st. 3", stop = "nedre"), "sagelva")
  expect_equal(name_tokens("Bekk til Lianvatnet", stop = "bekk"), "lianvatnet")
})

st_row <- function(...) {
  d <- as.data.frame(as.list(setNames(rep("", length(STATIONS_COLUMNS)), STATIONS_COLUMNS)))
  d$verified <- "no"
  a <- list(...)
  for (n in names(a)) d[[n]] <- a[[n]]
  d
}

test_that("validate_stations catches bad years, crs, coordinates and codes", {
  st <- rbind(st_row(survey_ref = "a", years = "2020", station = "1", crs = "EPSG:25832",
                     x = "569000", y = "7032000"),
              st_row(survey_ref = "zz", years = "20x0", station = "1"),
              st_row(survey_ref = "a", years = "2020", station = "2", crs = "EPSG:9999", x = "1", y = "2"),
              st_row(survey_ref = "a", years = "2020", station = "3", x = "1"),
              st_row(survey_ref = "a", years = "2020", station = "4", vannlokalitetkode = "123-R"))
  p <- validate_stations(st, "a")
  expect_false(1 %in% p$row)
  expect_true(all(c(2, 3, 4, 5) %in% p$row))
  expect_true(any(grepl("survey_ref", p$problem[p$row == 2])))
  expect_equal(nrow(validate_stations(st[, -1], "a")), 1)
})

test_that("survey_station_years expands years, picks a method and marks excluded stations", {
  gs <- data.frame(survey_ref = c("a", "b", "c"), title = "", institution = "",
                   region = c("", "Testby kommune, Sagelva", "Testby kommune, bekker"),
                   period = c("2019", "1978–1979", "2009"), documents = "", doc_ids = "")
  st <- rbind(st_row(survey_ref = "a", years = "2018;2020", station = "1", crs = "EPSG:4326",
                     x = "10.4", y = "63.4"),
              st_row(survey_ref = "a", years = "2020", station = "2", vannlokalitetkode = "123-1-R",
                     former_municipality = "Nabo"))
  cfg <- CFG
  cfg$name_stopwords <- "bekker"
  sy <- survey_station_years(gs, st, SCOPE, cfg)
  a <- sy[sy$survey_ref == "a", ]
  expect_equal(a$year, c(2018L, 2020L, 2020L))
  expect_equal(a$method, c("coords", "coords", "code"))
  expect_equal(a$excluded, c(FALSE, FALSE, TRUE))
  b <- sy[sy$survey_ref == "b", ]
  expect_equal(b$year, 1978:1979)
  expect_equal(unique(b$names), "sagelva")
  expect_equal(unique(b$method), "name")
  expect_equal(sy$method[sy$survey_ref == "c"], "none")  # "testby", "kommune", "bekker" are stop words
})

test_that("match_station_years matches by distance, code and name within the year", {
  recs <- data.frame(key = 1:5, datasetKey = "ds1", year = c(2020, 2020, 2019, 2020, 2020),
                     decimalLatitude = c(63.4, 63.41, 63.4, NA, NA),
                     decimalLongitude = c(10.4, 10.4, 10.4, NA, NA),
                     waterBody = c("", "", "", "Vannlokalitetkode: 123-1-R", ""),
                     locality = c("", "", "", "", "Sagelva ved brua"), locationID = NA)
  sy <- data.frame(survey_ref = "a", station = c("1", "2", "3"), year = 2020L,
                   lon = c(10.401, NA, NA), lat = c(63.4, NA, NA), code = c("", "123-1-R", ""),
                   names = c("", "", "sagelva"), method = c("coords", "code", "name"),
                   excluded = FALSE, station_source = "x")
  m <- match_station_years(sy, recs, CFG)
  # coords: record 1 at ~50 m counts, record 2 at ~1.1 km does not, record 3 is 2019.
  expect_equal(m$station_years$n_records, c(1L, 1L, 1L))
  expect_equal(sort(m$hits$rec), c(1L, 4L, 5L))
  # A station with coordinates far off but a matching code is matched by the code.
  sy2 <- sy[1, ]
  sy2$lon <- 11
  sy2$code <- "123-1-R"
  expect_equal(match_station_years(sy2, recs, CFG)$hits$rec, 4L)
})

test_that("match_score ignores dimensions that could not be assessed", {
  ev <- data.frame(place_time = c(1, 0, NA, 0.5), institution = c(1, 0, NA, NA),
                   dataset_name = c(0, 0, NA, 1), direct_link = c(NA, NA, NA, 1))
  s <- match_score(ev, CFG$weights)
  expect_equal(s, c(5 / 6, 0, NA, (2 + 1 + 3) / 8))
})

test_that("match_band is asymmetric: not_in_gbif needs low score, no coverage and located stations", {
  b <- match_band(score = c(0.9, 0.5, 0.3, 0.05, 0.05, 0.05, NA, 0),
                  coverage = c(1, 0.5, 0.2, 0, 0, NA, NA, 0),
                  located = c(1, 1, 1, 1, 0.5, 1, 1, 0.8), CFG$bands)
  expect_equal(as.character(b), c("likely_in_gbif", "likely_in_gbif", "uncertain",
                                  "likely_not_in_gbif", "uncertain", "uncertain", "uncertain",
                                  "likely_not_in_gbif"))
  expect_equal(levels(b), BANDS)
})

test_that("wilson_ci matches known values and handles edges", {
  ci <- wilson_ci(0, 10)
  expect_equal(unname(ci["lower"]), 0)
  expect_equal(unname(ci["upper"]), 0.2775, tolerance = 1e-3)
  ci <- wilson_ci(5, 10)
  expect_equal(unname(ci), c(0.2366, 0.7634), tolerance = 1e-3)
  ci <- wilson_ci(10, 10)
  expect_equal(unname(ci["upper"]), 1)
  expect_true(all(is.na(wilson_ci(0, 0))))
})

test_that("match_metrics counts false unpublished, false published and uncertain", {
  res <- data.frame(survey_ref = paste0("s", 1:6),
                    expected_status = c("in_gbif", "partly_in_gbif", "in_gbif", "open_elsewhere",
                                        "exists_not_available", "todo"),
                    band = factor(c("likely_not_in_gbif", "uncertain", "likely_in_gbif",
                                    "likely_in_gbif", "likely_not_in_gbif", "uncertain"),
                                  levels = BANDS))
  m <- match_metrics(res)
  expect_equal(m$false_unpublished$count, 1)
  expect_equal(m$false_unpublished$n, 3)
  expect_equal(m$false_published$count, 1)
  expect_equal(m$false_published$n, 2)
  expect_equal(m$uncertain$count, 2)
  expect_equal(m$uncertain$n, 6)
  expect_equal(sort(m$errors), c("s1", "s4"))
  ct <- confusion_table(res)
  expect_equal(sum(ct[, BANDS]), 6)
})

test_that("document_needles pulls ids and report numbers", {
  n <- document_needles("NINA Rapport 1988; NTNU VM naturhistorisk notat 2018-7",
                        "nva:0198abc;doi:10.1/x")
  expect_true(all(c("0198abc", "10.1/x", "rapport 1988", "notat 2018-7") %in% n))
})

test_that("institution_names drops the client and years", {
  expect_equal(institution_names("Rambøll Norge AS; Uni Research Miljø (Bergen) 2017–2022"),
               c("Rambøll Norge AS", "Uni Research Miljø (Bergen)"))
  expect_equal(institution_names("NINA (oppdragsgiver Trondheim kommune)"), "NINA")
})

test_that("survey_evidence weights name-only station-years in place × time, not in coverage", {
  g <- data.frame(survey_ref = "a", title = "", institution = "", region = "", period = "2020",
                  documents = "", doc_ids = "")
  sy <- data.frame(survey_ref = "a", station = c("1", "2"), year = 2020L, method = c("coords", "name"),
                   excluded = FALSE, n_records = c(0L, 3L))
  recs <- data.frame(key = 1:3, datasetKey = "ds1", year = 2020, order = "Plecoptera",
                     recordedBy = "", institutionCode = "", datasetName = "")
  hits <- data.frame(survey_ref = "a", rec = 1:3)
  ds <- data.frame(dataset_key = "ds1", title = "", publisher = "", meta_text = "")
  ev <- survey_evidence(g, sy, hits, recs, ds, CFG, character())
  expect_equal(ev$coverage, 0.5)
  expect_equal(ev$place_time, 0.25)
  expect_equal(ev$located, 0.5)
})

