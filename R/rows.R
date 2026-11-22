# Records sent to the model in steps 2 and 3, and the table rows made from its
# answers (`screening`, `extraction`, `extraction_survey` and their *_cmp
# copies). Uses join() from R/llm.R.

#' Screening record: title, abstract, keywords, publisher and year.
screen_record <- function(d) {
  val <- function(x, empty) if (is.na(x) || !nzchar(trimws(x))) empty else x
  paste(c(paste("Title:", val(d$title, "(no title)")),
          paste("Abstract:", val(d$abstract, "(no abstract)")),
          paste("Keywords:", val(gsub(";", "; ", d$tags), "(none)")),
          paste("Publisher:", val(d$publisher, "(not given)")),
          paste("Year:", val(as.character(d$year), "(not given)"))),
        collapse = "\n")
}

#' Call columns shared by `screening` and `extraction`.
call_columns <- function(res, model, thinking, prompt_file, prompt_sha, record) {
  data.frame(
    model = model, model_ids = join(res$models), prompt_file = prompt_file,
    prompt_sha256 = prompt_sha, n_chars_in = nchar(record), input_tokens = res$input_tokens,
    cache_creation_input_tokens = res$cache_creation_input_tokens,
    cache_read_input_tokens = res$cache_read_input_tokens,
    output_tokens = res$output_tokens, thinking_tokens = res$thinking_tokens,
    thinking = thinking, cost_usd = res$cost_usd, seconds = res$seconds)
}

#' One `screening` row.
screen_row <- function(id, res, model, thinking, prompt_file, prompt_sha, record, now) {
  o <- res$output
  cbind(data.frame(document_id = id, category = o$category, confidence = o$confidence,
                   taxon_groups = join(o$taxon_groups), reason = o$reason,
                   borderline = o$borderline, screened_at = now),
        call_columns(res, model, thinking, prompt_file, prompt_sha, record))
}

#' One `extraction` row.
extraction_row <- function(id, res, model, thinking, prompt_file, prompt_sha, record, now) {
  o <- res$output
  cbind(data.frame(
    document_id = id, eligible = o$eligible, eligible_reason = o$eligible_reason,
    borderline = o$borderline, borderline_reason = o$borderline_reason,
    producer = o$producer, commissioner = o$commissioner, funders = join(o$funders),
    funding_type = o$funding_type, study_type = o$study_type,
    study_context_page = o$study_context_page, n_surveys = length(o$surveys),
    more_surveys = o$more_surveys, extracted_at = now),
    call_columns(res, model, thinking, prompt_file, prompt_sha, record))
}

#' `extraction_survey` rows (NULL when there are no surveys). n_sites -1 (not
#' stated) becomes NA.
survey_rows <- function(id, surveys) {
  do.call(rbind, lapply(seq_along(surveys), function(k) {
    s <- surveys[[k]]
    data.frame(
      document_id = id, survey_no = k, taxon_groups = join(s$taxon_groups),
      taxa_names = join(s$taxa_names), years = join(s$years), months = join(s$months),
      places_json = as.character(jsonlite::toJSON(s$places, auto_unbox = TRUE)),
      n_sites = if (s$n_sites == -1) NA_integer_ else as.integer(s$n_sites),
      methods = join(s$methods), method_text = s$method_text,
      fieldwork_by = s$fieldwork_by, effort_stated = s$effort_stated,
      absences_stated = s$absences_stated, data_form = join(s$data_form),
      data_statement = s$data_statement, data_statement_quote = s$data_statement_quote,
      pages = join(s$pages))
  }))
}
