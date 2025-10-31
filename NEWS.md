# icdsnomedr 1.0.0

## Initial Release (2025-10-31)

### Features

* **Core Mapping Function** (`icd_to_snomed_mapper`)
  * Maps ICD-9 and ICD-10 codes to SNOMED CT concepts
  * Direct 'Maps to' relationship support
  * Hierarchical fallback mechanism (ancestors and descendants)
  * Concept relationship exploration (incoming and outgoing)
  * Multi-level relationship traversal

### Mapping Quality

* Confidence scoring (HIGH, MEDIUM, LOW, MEDIUM-HIGH)
* Manual review flagging system
  * REQUIRES_MANUAL_REVIEW: Unmapped codes
  * REVIEW_RECOMMENDED: Indirect mappings with distance > 1
  * REVIEW_SUGGESTED: Indirect mappings with distance = 1
  * EXPANDED_OPTIONS: Multiple options from direct mapping
  * MAPPED: Successful direct mappings
* Detailed mapping explanations in `review_reason` column
* Integration with Achilles results for concept frequency counts

### Configuration Options

* `only_standard`: Filter to standard concepts only
* `only_direct`: Limit to direct (1-level) relationships
* `max_mapping_distance`: Control relationship exploration depth
* `filter_domain`: Domain-specific filtering (Condition, Drug, etc.)
* Configurable database sources for OMOP CDM and Achilles

### Mapping Types

* **DIRECT**: Direct 'Maps to' relationship (HIGH confidence)
* **RELATED_DESCENDANT**: More specific concept via hierarchy
* **RELATED_ANCESTOR**: Broader concept via hierarchy
* **RELATED_RELATIONSHIP**: Via other concept relationships
* **DIRECT_THEN_DESCENDANT**: Expansion from direct mapping to descendants
* **DIRECT_THEN_ANCESTOR**: Expansion from direct mapping to ancestors
* **DIRECT_THEN_RELATIONSHIP**: Expansion from direct mapping via relationships
* **UNMAPPED**: Code found in OMOP but no SNOMED mapping
* **NOT_FOUND_IN_OMOP**: Code not found in OMOP vocabulary

### Documentation

* Comprehensive README with quick start guide
* Full function documentation with examples
* MIT License
* GitHub repository setup

### Dependencies

* DBI
* odbc
* DatabaseConnector
* dplyr
* CDMConnector
* SqlRender
* tidyr
* glue

### Database Support

* Amazon Redshift (primary)
* Any JDBC-compatible database supported by DatabaseConnector

### Input/Output

* **Input**: Data frame with columns:
  * `input_variable_name`: Descriptive name
  * `input_code`: ICD code
  * `input_vocab`: Vocabulary ID (ICD9CM, ICD10CM)
* **Output**: Data frame with 20 columns including:
  * Source code information
  * SNOMED mapping details
  * Confidence and distance metrics
  * Review flags and explanations
  * Frequency counts

### Known Limitations

* Requires access to OMOP CDM database
* Achilles results database required for frequency counts
* Currently optimized for Amazon Redshift SQL dialect

### Future Enhancements

See GitHub issues for planned features and improvements.