# Example: Using icdsnomedr to Map ICD Codes to SNOMED CT
#
# This script demonstrates how to use the icdsnomedr package to map
# ICD-9 and ICD-10 codes to SNOMED CT concepts using OMOP CDM.

library(icdsnomedr)
library(DatabaseConnector)

# ============================================================================
# STEP 1: Create Database Connection
# ============================================================================

# Set up connection details
connectionDetails <- createConnectionDetails(
  dbms   = "redshift",
  server = Sys.getenv("SERVER_SERVERLESS"),
  user   = Sys.getenv("USERNAME"),
  password = Sys.getenv("PASSWORD"),
  port     = "5439",
  pathToDriver = "~"
)

# Connect to database
con <- connect(connectionDetails)

# ============================================================================
# STEP 2: Prepare Input Data
# ============================================================================

# Example 1: Stomach Cancer Codes
input_data_cancer <- data.frame(
  input_variable_name = c("Stomach Cancer", "Stomach Cancer", "Stomach Cancer", "Stomach Cancer"),
  input_code = c("C16.1", "C16.2", "C16.3", "151"),
  input_vocab = c("ICD10CM", "ICD10CM", "ICD10CM", "ICD9CM"),
  stringsAsFactors = FALSE
)

# Example 2: Inflammatory Bowel Disease
input_data_ibd <- data.frame(
  input_variable_name = c("Inflammatory Bowel Disease", "Inflammatory Bowel Disease"),
  input_code = c("556.9", "K50.00"),
  input_vocab = c("ICD9CM", "ICD10CM"),
  stringsAsFactors = FALSE
)

# ============================================================================
# STEP 3: Run Mapping with Default Settings
# ============================================================================

results_default <- icd_to_snomed_mapper(
  con = con,
  input_data = input_data_cancer,
  database_name = "healthverity_marketplace_omop_20250331",
  achilles_database = "desc_jp_claims_all_omop_latest",
  only_standard = TRUE,
  only_direct = FALSE,
  max_mapping_distance = 5,
  filter_domain = "Condition"
)

# View results
View(results_default)

# ============================================================================
# STEP 4: Run Mapping with Only Direct Relationships
# ============================================================================

results_direct <- icd_to_snomed_mapper(
  con = con,
  input_data = input_data_ibd,
  only_standard = TRUE,
  only_direct = TRUE,     # Only direct relationships
  max_mapping_distance = 1
)

View(results_direct)

# ============================================================================
# STEP 5: Analyze Results
# ============================================================================

# Summary by mapping type
table(results_default$mapping_type)

# Summary by confidence level
table(results_default$mapping_confidence)

# Summary by review flag
table(results_default$review_flag)

# Codes requiring manual review
codes_needing_review <- results_default[
  results_default$review_flag == "REQUIRES_MANUAL_REVIEW",
]

# High confidence mappings only
high_confidence <- results_default[
  results_default$mapping_confidence == "HIGH",
]

# ============================================================================
# STEP 6: Export Results
# ============================================================================

# Export to CSV
write.csv(results_default, "icd_snomed_mapping_results.csv", row.names = FALSE)

# ============================================================================
# STEP 7: Disconnect
# ============================================================================

disconnect(con)