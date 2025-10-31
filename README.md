# icdsnomedr <img src="man/figures/logo.png" align="right" height="139" />

<!-- badges: start -->
[![R-CMD-check](https://github.com/4ramvarmamake/icdsnomedr/workflows/R-CMD-check/badge.svg)](https://github.com/4ramvarmamake/icdsnomedr/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Project Status: Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
<!-- badges: end -->

**icdsnomedr** is an R package that maps ICD-9 and ICD-10 codes to SNOMED CT concepts using the OMOP Common Data Model (CDM). It provides intelligent fallback mechanisms with hierarchical and relationship-based exploration when direct mappings are unavailable.

## Features

✨ **Comprehensive Mapping**
- Direct 'Maps to' relationships from ICD to SNOMED CT
- Hierarchical fallback (ancestors and descendants)
- Concept relationship exploration
- Multi-level relationship traversal

🎯 **Quality Control**
- Confidence scoring (HIGH, MEDIUM, LOW)
- Manual review flagging for uncertain mappings
- Detailed mapping explanations
- Frequency counts from Achilles results

🔧 **Flexible Configuration**
- Filter by standard concepts
- Control relationship depth
- Domain-specific filtering (Condition, Drug, etc.)
- Customizable database sources

## Installation

You can install the development version from GitHub:

```r
# install.packages("devtools")
devtools::install_github("4ramvarmamake/icdsnomedr")
```

## Prerequisites

- Access to an OMOP CDM database (Redshift, PostgreSQL, etc.)
- DatabaseConnector package configured
- OMOP vocabulary tables (concept, concept_relationship, concept_ancestor)
- Achilles results database (optional, for frequency counts)

## Quick Start

```r
library(icdsnomedr)
library(DatabaseConnector)

# 1. Create database connection
connectionDetails <- createConnectionDetails(
  dbms = "redshift",
  server = Sys.getenv("SERVER_SERVERLESS"),
  user = Sys.getenv("USERNAME"),
  password = Sys.getenv("PASSWORD"),
  port = "5439",
  pathToDriver = "~"
)
con <- connect(connectionDetails)

# 2. Prepare input data
input_data <- data.frame(
  input_variable_name = c("Stomach Cancer", "Stomach Cancer", "Stomach Cancer", "Stomach Cancer"),
  input_code = c("C16.1", "C16.2", "C16.3", "151"),
  input_vocab = c("ICD10CM", "ICD10CM", "ICD10CM", "ICD9CM"),
  stringsAsFactors = FALSE
)

# 3. Run mapping
results <- icd_to_snomed_mapper(
  con = con,
  input_data = input_data,
  database_name = "healthverity_marketplace_omop_20250331",
  achilles_database = "desc_jp_claims_all_omop_latest",
  only_standard = TRUE,
  only_direct = FALSE,
  max_mapping_distance = 5,
  filter_domain = "Condition"
)

# 4. View results
View(results)

# 5. Disconnect
disconnect(con)
```

## Input Data Format

Your input data frame must have three columns:

| Column Name | Type | Description | Example |
|-------------|------|-------------|---------|
| `input_variable_name` | Character | Descriptive name for the code | "Inflammatory Bowel Disease" |
| `input_code` | Character | ICD code | "556.9", "K50.00" |
| `input_vocab` | Character | Vocabulary identifier | "ICD9CM", "ICD10CM" |

## Output

The function returns a data frame with detailed mapping information:

| Column | Description |
|--------|-------------|
| `input_code` | Original ICD code |
| `snomed_concept_id` | Mapped SNOMED concept ID |
| `snomed_name` | SNOMED concept name |
| `mapping_type` | Type of mapping (DIRECT, RELATED_DESCENDANT, etc.) |
| `mapping_confidence` | Confidence level (HIGH, MEDIUM, LOW) |
| `mapping_distance` | Distance in relationship hierarchy |
| `review_flag` | Manual review recommendation |
| `review_reason` | Explanation for review recommendation |
| `concept_id_condition_counts` | Frequency in Achilles database |

## Mapping Types

| Type | Description | Confidence |
|------|-------------|-----------|
| `DIRECT` | Direct 'Maps to' relationship | HIGH |
| `RELATED_DESCENDANT` | More specific concept via hierarchy | MEDIUM-LOW |
| `RELATED_ANCESTOR` | Broader concept via hierarchy | MEDIUM-LOW |
| `RELATED_RELATIONSHIP` | Via other concept relationships | LOW |
| `DIRECT_THEN_*` | Expansion from direct mapping | MEDIUM-HIGH |
| `UNMAPPED` | No mapping found | - |
| `NOT_FOUND_IN_OMOP` | Code not in vocabulary | - |

## Advanced Usage

### Filter Only Standard Concepts

```r
results <- icd_to_snomed_mapper(
  con = con,
  input_data = input_data,
  only_standard = TRUE,  # Only standard SNOMED concepts
  only_direct = FALSE,
  max_mapping_distance = 5
)
```

### Limit to Direct Relationships

```r
results <- icd_to_snomed_mapper(
  con = con,
  input_data = input_data,
  only_standard = TRUE,
  only_direct = TRUE,  # Only 1-level relationships
  max_mapping_distance = 1
)
```

### Map Drug Codes

```r
drug_data <- data.frame(
  input_variable_name = c("Aspirin"),
  input_code = c("A01AD05"),
  input_vocab = c("ATC"),
  stringsAsFactors = FALSE
)

results <- icd_to_snomed_mapper(
  con = con,
  input_data = drug_data,
  filter_domain = "Drug"  # Filter to Drug domain
)
```

## Review Flags

The function automatically flags mappings that may require manual review:

- `REQUIRES_MANUAL_REVIEW`: No mapping found or code not in OMOP
- `REVIEW_RECOMMENDED`: Indirect mapping with distance > 1
- `REVIEW_SUGGESTED`: Indirect mapping with distance = 1
- `EXPANDED_OPTIONS`: Multiple options from direct mapping
- `MAPPED`: Successful direct mapping

## Documentation

Full documentation is available at the [package website](https://4ramvarmamake.github.io/icdsnomedr/).

For function-level help:
```r
?icd_to_snomed_mapper
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Citation

If you use this package in your research, please cite:

```
@software{icdsnomedr,
  author = {4ramvarmamake},
  title = {icdsnomedr: ICD to SNOMED CT Concept Mapper for OMOP CDM},
  year = {2025},
  url = {https://github.com/4ramvarmamake/icdsnomedr}
}
```

## Acknowledgments

- Built for use with the [OMOP Common Data Model](https://ohdsi.github.io/CommonDataModel/)
- Uses [DatabaseConnector](https://ohdsi.github.io/DatabaseConnector/) for database connectivity
- Inspired by the OHDSI community

## Support

- 📧 Open an [issue](https://github.com/4ramvarmamake/icdsnomedr/issues) for bug reports
- 💬 Start a [discussion](https://github.com/4ramvarmamake/icdsnomedr/discussions) for questions
- 📖 Check the [documentation](https://4ramvarmamake.github.io/icdsnomedr/)

---

```
