# Build (or update) the register from db/schema.sql.
# Usage: Rscript scripts/00_build_db.R [path]   (default data/register.sqlite)

source("R/db.R")

args <- commandArgs(trailingOnly = TRUE)
path <- if (length(args)) args[[1]] else DEFAULT_DB_PATH

con <- db_connect(path)
on.exit(db_disconnect(con))
db_init(con)

cat("Register:", path, "\n")
for (t in db_tables(con)) cat(sprintf("  %-22s %6d rows\n", t, db_count(con, t)))
