#' Map ICD Codes to SNOMED CT Concepts
#'
#' This function maps ICD-9 and ICD-10 codes to SNOMED CT concepts using the
#' OMOP Common Data Model. It provides direct mappings via 'Maps to' relationships
#' and enhanced fallback mechanisms using hierarchical relationships and concept
#' relationships when direct mappings are not available.
#'
#' @param con A database connection object created with DatabaseConnector::connect()
#' @param input_data A data frame with columns: input_variable_name, input_code, input_vocab
#'   \itemize{
#'     \item input_variable_name: Descriptive name for the code (e.g., "Inflammatory Bowel Disease")
#'     \item input_code: The ICD code (e.g., "556.9", "K50.00")
#'     \item input_vocab: Vocabulary identifier (e.g., "ICD9CM", "ICD10CM")
#'   }
#' @param database_name Character string specifying the OMOP CDM database name
#'   (default: "healthverity_marketplace_omop_20250331")
#' @param achilles_database Character string specifying the Achilles results database
#'   for concept counts (default: "desc_jp_claims_all_omop_latest")
#' @param only_standard Logical indicating whether to return only standard concepts
#'   in fallback mappings (default: TRUE)
#' @param only_direct Logical indicating whether to use only direct (1-level)
#'   relationships in fallback (default: FALSE)
#' @param max_mapping_distance Integer specifying maximum relationship distance to
#'   explore (default: 5)
#' @param filter_domain Character string specifying the SNOMED domain to filter
#'   results (default: "Condition")
#'
#' @return A data frame containing mapping results with the following columns:
#'   \itemize{
#'     \item input_code: Original input ICD code
#'     \item input_vocab: Original input vocabulary
#'     \item input_variable_name: Original input variable name
#'     \item source_code: Source concept code from OMOP
#'     \item source_concept_name: Source concept name
#'     \item source_vocabulary: Source vocabulary ID
#'     \item snomed_concept_id: Mapped SNOMED concept ID
#'     \item snomed_code: Mapped SNOMED code
#'     \item snomed_name: Mapped SNOMED concept name
#'     \item snomed_domain: SNOMED domain
#'     \item standard_concept: Standard concept flag
#'     \item relationship_id: Relationship type used for mapping
#'     \item mapping_type: Type of mapping (DIRECT, RELATED_DESCENDANT, etc.)
#'     \item mapping_confidence: Confidence level (HIGH, MEDIUM, LOW)
#'     \item mapping_distance: Distance in relationship hierarchy
#'     \item rel_category: Relationship category
#'     \item direction: Relationship direction
#'     \item review_flag: Manual review recommendation flag
#'     \item review_reason: Explanation for review flag
#'     \item concept_id_condition_counts: Frequency count from Achilles
#'   }
#'
#' @details
#' The function performs mapping in multiple stages:
#' \enumerate{
#'   \item Direct 'Maps to' relationships to SNOMED
#'   \item Hierarchical exploration (descendants and ancestors)
#'   \item Concept relationship exploration (incoming and outgoing)
#'   \item Flagging of unmapped codes for manual review
#' }
#'
#' Mapping types include:
#' \itemize{
#'   \item DIRECT: Direct 'Maps to' relationship
#'   \item RELATED_DESCENDANT: More specific concept via hierarchy
#'   \item RELATED_ANCESTOR: Broader concept via hierarchy
#'   \item RELATED_RELATIONSHIP: Related via concept relationship
#'   \item DIRECT_THEN_*: Expansion from direct mapping
#'   \item UNMAPPED: No mapping found
#'   \item NOT_FOUND_IN_OMOP: Code not in vocabulary
#' }
#'
#' @examples
#' \dontrun{
#' # Create connection
#' connectionDetails <- DatabaseConnector::createConnectionDetails(
#'   dbms = "redshift",
#'   server = Sys.getenv("SERVER_SERVERLESS"),
#'   user = Sys.getenv("USERNAME"),
#'   password = Sys.getenv("PASSWORD"),
#'   port = "5439",
#'   pathToDriver = "~"
#' )
#' con <- DatabaseConnector::connect(connectionDetails)
#'
#' # Prepare input data
#' input_data <- data.frame(
#'   input_variable_name = c("Stomach Cancer", "Stomach Cancer"),
#'   input_code = c("C16.1", "151"),
#'   input_vocab = c("ICD10CM", "ICD9CM"),
#'   stringsAsFactors = FALSE
#' )
#'
#' # Run mapping
#' results <- icd_to_snomed_mapper(
#'   con = con,
#'   input_data = input_data,
#'   only_standard = TRUE,
#'   only_direct = FALSE,
#'   max_mapping_distance = 5,
#'   filter_domain = "Condition"
#' )
#'
#' # View results
#' View(results)
#'
#' # Disconnect
#' DatabaseConnector::disconnect(con)
#' }
#'
#' @importFrom DBI dbGetQuery
#' @export
icd_to_snomed_mapper <- function(
    con,
    input_data,
    database_name = "healthverity_marketplace_omop_20250331",
    achilles_database = "desc_jp_claims_all_omop_latest",
    only_standard = TRUE,
    only_direct = FALSE,
    max_mapping_distance = 5,
    filter_domain = "Condition"
) {
  
  # Validate input_data structure
  if (!all(c("input_variable_name", "input_code", "input_vocab") %in% names(input_data))) {
    stop("input_data must have columns: input_variable_name, input_code, input_vocab")
  }
  
  # Validate connection
  if (!inherits(con, "DatabaseConnectorConnection") && !inherits(con, "JdbcConnection")) {
    stop("con must be a valid database connection created with DatabaseConnector::connect()")
  }
  
  # Validate numeric parameters
  if (!is.numeric(max_mapping_distance) || max_mapping_distance < 1) {
    stop("max_mapping_distance must be a positive integer")
  }
  
  # Create the input_codes CTE string from the data frame
  input_codes_sql <- paste0(
    "SELECT '", input_data$input_variable_name, "' AS input_variable_name, ",
    "'", input_data$input_code, "' AS input_code, ",
    "'", input_data$input_vocab, "' AS input_vocab",
    collapse = "\n    UNION ALL "
  )
  
  # Convert boolean to SQL boolean strings
  only_standard_sql <- toupper(as.character(only_standard))
  only_direct_sql <- toupper(as.character(only_direct))
  
  # Build the complete query
  query <- paste0("
-- ICD-9 and ICD-10 to SNOMED Concept Mapper with Manual Review Flagging
-- Enhanced with hierarchical and relationship-based fallback for ALL codes
-- For use with OMOP CDM on Amazon Redshift

WITH input_codes AS (
    ", input_codes_sql, "
),

-- Control parameters for relationship exploration
ctl AS (
    SELECT 
        ", only_standard_sql, " AS only_standard,  -- Only return standard concepts in fallback
        ", only_direct_sql, " AS only_direct     -- Allow multi-level relationships
),

-- Step 1: Find source concepts for input ICD codes
source_concepts AS (
    SELECT 
        ic.input_code,
        ic.input_vocab,
        ic.input_variable_name,
        c.concept_id AS source_concept_id,
        c.concept_code,
        c.concept_name AS source_concept_name,
        c.vocabulary_id,
        c.domain_id,
        c.invalid_reason
    FROM input_codes ic
    LEFT JOIN ", database_name, ".concept c 
        ON UPPER(TRIM(ic.input_code)) = UPPER(TRIM(c.concept_code))
        AND c.vocabulary_id = ic.input_vocab
),

-- Step 2: Direct 'Maps to' relationship to SNOMED
direct_mappings AS (
    SELECT 
        sc.input_code,
        sc.input_vocab,
        sc.input_variable_name,
        sc.source_concept_id,
        sc.concept_code AS source_code,
        sc.source_concept_name,
        sc.vocabulary_id AS source_vocabulary,
        cr.relationship_id,
        c_target.concept_id AS snomed_concept_id,
        c_target.concept_code AS snomed_code,
        c_target.concept_name AS snomed_name,
        c_target.standard_concept,
        c_target.domain_id AS snomed_domain,
        'DIRECT' AS mapping_type,
        'HIGH' AS mapping_confidence,
        0 AS mapping_distance,
        NULL AS rel_category,
        NULL AS direction
    FROM source_concepts sc
    INNER JOIN ", database_name, ".concept_relationship cr 
        ON sc.source_concept_id = cr.concept_id_1
        AND cr.relationship_id = 'Maps to'
        AND cr.invalid_reason IS NULL
        AND CURRENT_DATE BETWEEN cr.valid_start_date AND cr.valid_end_date
    INNER JOIN ", database_name, ".concept c_target 
        ON cr.concept_id_2 = c_target.concept_id
        AND c_target.vocabulary_id = 'SNOMED'
        AND c_target.invalid_reason IS NULL
        AND c_target.standard_concept = 'S'
),

-- Step 3: Enhanced fallback - TWO SCENARIOS
-- Scenario A: Explore from SNOMED concepts that were directly mapped
-- Scenario B: Explore from ICD source concepts that have NO direct mapping

-- 3a: Seed concepts - BOTH directly mapped SNOMED AND unmapped ICD codes
seed_from_direct AS (
    SELECT DISTINCT
        dm.input_code,
        dm.input_vocab,
        dm.input_variable_name,
        dm.source_concept_id,
        dm.source_code,
        dm.source_concept_name,
        dm.source_vocabulary,
        c.concept_id,
        c.concept_code,
        c.concept_name,
        c.vocabulary_id,
        c.domain_id,
        c.standard_concept,
        c.invalid_reason,
        'FROM_DIRECT_MAP' AS seed_origin
    FROM direct_mappings dm
    JOIN ", database_name, ".concept c
        ON c.concept_id = dm.snomed_concept_id
),

seed_from_unmapped_icd AS (
    SELECT DISTINCT
        sc.input_code,
        sc.input_vocab,
        sc.input_variable_name,
        sc.source_concept_id,
        sc.concept_code AS source_code,
        sc.source_concept_name,
        sc.vocabulary_id AS source_vocabulary,
        sc.source_concept_id AS concept_id,
        sc.concept_code,
        sc.source_concept_name AS concept_name,
        sc.vocabulary_id,
        sc.domain_id,
        CAST(NULL AS VARCHAR(1)) AS standard_concept,
        sc.invalid_reason,
        'FROM_UNMAPPED_ICD' AS seed_origin
    FROM source_concepts sc
    WHERE NOT EXISTS (
        SELECT 1 
        FROM direct_mappings dm 
        WHERE dm.input_code = sc.input_code 
        AND dm.input_vocab = sc.input_vocab
    )
    AND sc.source_concept_id IS NOT NULL
),

seed AS (
    SELECT * FROM seed_from_direct
    UNION ALL
    SELECT * FROM seed_from_unmapped_icd
),

-- 3b: Descendants of seed concepts
descendants AS (
    SELECT
        s.input_code,
        s.input_vocab,
        s.input_variable_name,
        s.source_concept_id,
        s.source_code,
        s.source_concept_name,
        s.source_vocabulary,
        s.seed_origin,
        s.concept_id                   AS seed_snomed_concept_id,
        s.concept_name                 AS seed_snomed_concept_name,
        'HIERARCHY_DESCENDANT'         AS rel_category,
        'descendant_of'                AS direction,
        ca.min_levels_of_separation    AS levels_of_separation,
        CAST(NULL AS VARCHAR)          AS relationship_id,
        c2.concept_id                  AS related_concept_id,
        c2.concept_name                AS related_concept_name,
        c2.concept_code                AS related_concept_code,
        c2.vocabulary_id,
        c2.domain_id,
        c2.standard_concept,
        c2.invalid_reason
    FROM seed s
    JOIN ", database_name, ".concept_ancestor ca
        ON ca.ancestor_concept_id = s.concept_id
    JOIN ", database_name, ".concept c2
        ON c2.concept_id = ca.descendant_concept_id
    JOIN ctl ON 1=1
    WHERE s.concept_id <> c2.concept_id
        AND c2.invalid_reason IS NULL
        AND c2.vocabulary_id = 'SNOMED'
        AND (NOT ctl.only_standard OR c2.standard_concept = 'S')
        AND (NOT ctl.only_direct OR ca.min_levels_of_separation = 1)
),

-- 3c: Ancestors of seed concepts
ancestors AS (
    SELECT
        s.input_code,
        s.input_vocab,
        s.input_variable_name,
        s.source_concept_id,
        s.source_code,
        s.source_concept_name,
        s.source_vocabulary,
        s.seed_origin,
        s.concept_id                   AS seed_snomed_concept_id,
        s.concept_name                 AS seed_snomed_concept_name,
        'HIERARCHY_ANCESTOR'           AS rel_category,
        'ancestor_of'                  AS direction,
        ca.min_levels_of_separation    AS levels_of_separation,
        CAST(NULL AS VARCHAR)          AS relationship_id,
        c1.concept_id                  AS related_concept_id,
        c1.concept_name                AS related_concept_name,
        c1.concept_code                AS related_concept_code,
        c1.vocabulary_id,
        c1.domain_id,
        c1.standard_concept,
        c1.invalid_reason
    FROM seed s
    JOIN ", database_name, ".concept_ancestor ca
        ON ca.descendant_concept_id = s.concept_id
    JOIN ", database_name, ".concept c1
        ON c1.concept_id = ca.ancestor_concept_id
    JOIN ctl ON 1=1
    WHERE s.concept_id <> c1.concept_id
        AND c1.invalid_reason IS NULL
        AND c1.vocabulary_id = 'SNOMED'
        AND (NOT ctl.only_standard OR c1.standard_concept = 'S')
        AND (NOT ctl.only_direct OR ca.min_levels_of_separation = 1)
),

-- 3d: Outgoing relationships from seed concepts
cr_out AS (
    SELECT
        s.input_code,
        s.input_vocab,
        s.input_variable_name,
        s.source_concept_id,
        s.source_code,
        s.source_concept_name,
        s.source_vocabulary,
        s.seed_origin,
        s.concept_id                   AS seed_snomed_concept_id,
        s.concept_name                 AS seed_snomed_concept_name,
        'RELATIONSHIP'                 AS rel_category,
        'outgoing'                     AS direction,
        CAST(NULL AS INTEGER)          AS levels_of_separation,
        cr.relationship_id             AS relationship_id,
        c2.concept_id                  AS related_concept_id,
        c2.concept_name                AS related_concept_name,
        c2.concept_code                AS related_concept_code,
        c2.vocabulary_id,
        c2.domain_id,
        c2.standard_concept,
        c2.invalid_reason
    FROM seed s
    JOIN ", database_name, ".concept_relationship cr
        ON cr.concept_id_1 = s.concept_id
    JOIN ", database_name, ".concept c2
        ON c2.concept_id = cr.concept_id_2
    JOIN ctl ON 1=1
    WHERE cr.invalid_reason IS NULL
        AND CURRENT_DATE BETWEEN cr.valid_start_date AND cr.valid_end_date
        AND c2.invalid_reason IS NULL
        AND c2.vocabulary_id = 'SNOMED'
        AND (NOT ctl.only_standard OR c2.standard_concept = 'S')
),

-- 3e: Incoming relationships to seed concepts
cr_in AS (
    SELECT
        s.input_code,
        s.input_vocab,
        s.input_variable_name,
        s.source_concept_id,
        s.source_code,
        s.source_concept_name,
        s.source_vocabulary,
        s.seed_origin,
        s.concept_id                   AS seed_snomed_concept_id,
        s.concept_name                 AS seed_snomed_concept_name,
        'RELATIONSHIP'                 AS rel_category,
        'incoming'                     AS direction,
        CAST(NULL AS INTEGER)          AS levels_of_separation,
        cr.relationship_id             AS relationship_id,
        c1.concept_id                  AS related_concept_id,
        c1.concept_name                AS related_concept_name,
        c1.concept_code                AS related_concept_code,
        c1.vocabulary_id,
        c1.domain_id,
        c1.standard_concept,
        c1.invalid_reason
    FROM seed s
    JOIN ", database_name, ".concept_relationship cr
        ON cr.concept_id_2 = s.concept_id
    JOIN ", database_name, ".concept c1
        ON c1.concept_id = cr.concept_id_1
    JOIN ctl ON 1=1
    WHERE cr.invalid_reason IS NULL
        AND CURRENT_DATE BETWEEN cr.valid_start_date AND cr.valid_end_date
        AND c1.invalid_reason IS NULL
        AND c1.vocabulary_id = 'SNOMED'
        AND (NOT ctl.only_standard OR c1.standard_concept = 'S')
),

-- 3f: Combine all related concepts
all_related AS (
    SELECT * FROM descendants
    UNION ALL
    SELECT * FROM ancestors
    UNION ALL
    SELECT * FROM cr_out
    UNION ALL
    SELECT * FROM cr_in
),

-- 3g: Convert related concepts to mapping format
related_mappings AS (
    SELECT 
        ar.input_code,
        ar.input_vocab,
        ar.input_variable_name,
        ar.source_concept_id,
        ar.source_code,
        ar.source_concept_name,
        ar.source_vocabulary,
        ar.relationship_id,
        ar.related_concept_id AS snomed_concept_id,
        ar.related_concept_code AS snomed_code,
        ar.related_concept_name AS snomed_name,
        ar.standard_concept,
        ar.domain_id AS snomed_domain,
        CASE 
            WHEN ar.seed_origin = 'FROM_DIRECT_MAP' AND ar.rel_category = 'HIERARCHY_DESCENDANT' THEN 'DIRECT_THEN_DESCENDANT'
            WHEN ar.seed_origin = 'FROM_DIRECT_MAP' AND ar.rel_category = 'HIERARCHY_ANCESTOR' THEN 'DIRECT_THEN_ANCESTOR'
            WHEN ar.seed_origin = 'FROM_DIRECT_MAP' AND ar.rel_category = 'RELATIONSHIP' THEN 'DIRECT_THEN_RELATIONSHIP'
            WHEN ar.seed_origin = 'FROM_UNMAPPED_ICD' AND ar.rel_category = 'HIERARCHY_DESCENDANT' THEN 'RELATED_DESCENDANT'
            WHEN ar.seed_origin = 'FROM_UNMAPPED_ICD' AND ar.rel_category = 'HIERARCHY_ANCESTOR' THEN 'RELATED_ANCESTOR'
            WHEN ar.seed_origin = 'FROM_UNMAPPED_ICD' AND ar.rel_category = 'RELATIONSHIP' THEN 'RELATED_RELATIONSHIP'
        END AS mapping_type,
        CASE 
            WHEN ar.seed_origin = 'FROM_DIRECT_MAP' THEN 'MEDIUM-HIGH'
            WHEN ar.rel_category = 'HIERARCHY_DESCENDANT' AND ar.levels_of_separation = 1 THEN 'MEDIUM'
            WHEN ar.rel_category = 'HIERARCHY_ANCESTOR' AND ar.levels_of_separation = 1 THEN 'MEDIUM'
            ELSE 'LOW'
        END AS mapping_confidence,
        COALESCE(ar.levels_of_separation, 1) AS mapping_distance,
        ar.rel_category,
        ar.direction
    FROM all_related ar
),

-- Step 4: Union direct and related mappings
all_mappings AS (
    SELECT * FROM direct_mappings
    UNION ALL
    SELECT * FROM related_mappings
),

-- Step 5: Identify codes with NO mappings at all for manual review
unmapped_codes AS (
    SELECT 
        sc.input_code,
        sc.input_vocab,
        sc.input_variable_name, 
        sc.source_concept_id,
        sc.concept_code AS source_code,
        sc.source_concept_name,
        sc.vocabulary_id AS source_vocabulary,
        NULL AS relationship_id,
        NULL AS snomed_concept_id,
        NULL AS snomed_code,
        NULL AS snomed_name,
        NULL AS standard_concept,
        NULL AS snomed_domain,
        'UNMAPPED' AS mapping_type,
        NULL AS mapping_confidence,
        999 AS mapping_distance,
        NULL AS rel_category,
        NULL AS direction
    FROM source_concepts sc
    WHERE NOT EXISTS (
        SELECT 1 
        FROM all_mappings am 
        WHERE am.input_code = sc.input_code 
        AND am.input_vocab = sc.input_vocab
    )
    AND sc.source_concept_id IS NOT NULL
),

-- Step 6: Handle completely unknown codes (not even in OMOP)
unknown_codes AS (
    SELECT 
        ic.input_code,
        ic.input_vocab,
        ic.input_variable_name,
        NULL AS source_concept_id,
        ic.input_code AS source_code,
        NULL AS source_concept_name,
        ic.input_vocab AS source_vocabulary,
        NULL AS relationship_id,
        NULL AS snomed_concept_id,
        NULL AS snomed_code,
        NULL AS snomed_name,
        NULL AS standard_concept,
        NULL AS snomed_domain,
        'NOT_FOUND_IN_OMOP' AS mapping_type,
        NULL AS mapping_confidence,
        999 AS mapping_distance,
        NULL AS rel_category,
        NULL AS direction
    FROM input_codes ic
    WHERE NOT EXISTS (
        SELECT 1 
        FROM source_concepts sc 
        WHERE sc.input_code = ic.input_code 
        AND sc.input_vocab = ic.input_vocab
        AND sc.source_concept_id IS NOT NULL
    )
),

-- Step 7: Combine all results
final_results AS (
    SELECT * FROM all_mappings
    UNION ALL
    SELECT * FROM unmapped_codes
    UNION ALL
    SELECT * FROM unknown_codes
),

-- Step 7.5: Count from Achilles OMOP CDM
achilles_table_condition AS (
    SELECT 
        COUNT(*) AS concept_id_count,
        condition_concept_id  
    FROM ", achilles_database, ".condition_occurrence
    GROUP BY condition_concept_id
)

-- Step 8: Final output with manual review flag and enhanced metadata
SELECT 
    fr.input_code,
    fr.input_vocab,
    fr.input_variable_name,
    fr.source_code,
    fr.source_concept_name,
    fr.source_vocabulary,
    fr.snomed_concept_id,
    fr.snomed_code,
    fr.snomed_name,
    fr.snomed_domain,
    fr.standard_concept,
    fr.relationship_id,
    fr.mapping_type,
    fr.mapping_confidence,
    fr.mapping_distance,
    fr.rel_category,
    fr.direction,
    CASE 
        WHEN fr.mapping_type IN ('UNMAPPED', 'NOT_FOUND_IN_OMOP') THEN 'REQUIRES_MANUAL_REVIEW'
        WHEN fr.mapping_type LIKE 'RELATED%' AND fr.mapping_distance > 1 THEN 'REVIEW_RECOMMENDED'
        WHEN fr.mapping_type LIKE 'RELATED%' THEN 'REVIEW_SUGGESTED'
        WHEN fr.mapping_type LIKE 'DIRECT_THEN%' THEN 'EXPANDED_OPTIONS'
        ELSE 'MAPPED'
    END AS review_flag,
    CASE 
        WHEN fr.mapping_type = 'NOT_FOUND_IN_OMOP' THEN 'Code not found in OMOP vocabulary'
        WHEN fr.mapping_type = 'UNMAPPED' THEN 'Code exists but has no SNOMED mapping or relationships'
        WHEN fr.mapping_type = 'RELATED_DESCENDANT' THEN 'No direct map - found more specific descendant concept (distance=' || fr.mapping_distance || ')'
        WHEN fr.mapping_type = 'RELATED_ANCESTOR' THEN 'No direct map - found broader ancestor concept (distance=' || fr.mapping_distance || ')'
        WHEN fr.mapping_type = 'RELATED_RELATIONSHIP' THEN 'No direct map - found via ' || fr.direction || ' relationship: ' || COALESCE(fr.relationship_id, 'unspecified')
        WHEN fr.mapping_type = 'DIRECT_THEN_DESCENDANT' THEN 'Direct map found + expanded to descendant concepts (distance=' || fr.mapping_distance || ')'
        WHEN fr.mapping_type = 'DIRECT_THEN_ANCESTOR' THEN 'Direct map found + expanded to ancestor concepts (distance=' || fr.mapping_distance || ')'
        WHEN fr.mapping_type = 'DIRECT_THEN_RELATIONSHIP' THEN 'Direct map found + expanded via ' || fr.direction || ' relationship: ' || COALESCE(fr.relationship_id, 'unspecified')
        ELSE NULL
    END AS review_reason,
    atc.concept_id_count as concept_id_condition_counts
FROM final_results fr
LEFT JOIN achilles_table_condition atc
    ON fr.snomed_concept_id = atc.condition_concept_id 
WHERE fr.mapping_distance < ", max_mapping_distance + 1, " 
    AND fr.snomed_domain = '", filter_domain, "'
ORDER BY 
    atc.concept_id_count ASC,
    fr.input_code,
    CASE 
        WHEN fr.mapping_type = 'DIRECT' THEN 1
        WHEN fr.mapping_type LIKE 'DIRECT_THEN%' THEN 2
        WHEN fr.mapping_type LIKE 'RELATED%' THEN 3
        WHEN fr.mapping_type = 'UNMAPPED' THEN 4
        ELSE 5
    END,
    fr.mapping_distance,
    fr.mapping_confidence DESC,
    fr.snomed_concept_id;
  ")
  
  # Execute the query
  result <- DBI::dbGetQuery(con, query)
  
  return(result)
}