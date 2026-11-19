#!/usr/bin/env python3
"""oxo-flow port of the nf-core/fetchngs input-id validation.

Validates every identifier in FILE_IN against the upstream SRA / ENA / DDBJ /
GEO accession regex and writes the stripped, deduplicated ids (upstream
`samplesheetToList(...)` + `.unique()`) to FILE_OUT.

In 1.12.0 this was the `isSraId` Groovy check of PIPELINE_INITIALISATION
(subworkflows/local/utils_nfcore_fetchngs_pipeline/main.nf); in 1.13.0
upstream moved the input validation into the input schema
(assets/schema_input.json, same regex, checked via the nf-schema plugin's
`samplesheetToList`), and oxo-flow has no such plugin — so this rule stays
as the port-side enforcement point for the byte-identical 1.13.0 schema
pattern. The upstream mixture-of-ids error wording belongs to the removed
1.12.0 `isSraId`; the offending-id reporting is kept.

Usage: check_ids.py <FILE_IN> <FILE_OUT>
"""

import re
import sys

# Regex identical in 1.12.0 `def isSraId(input)`
# (subworkflows/local/utils_nfcore_fetchngs_pipeline/main.nf) and in the
# 1.13.0 input schema items pattern (assets/schema_input.json)
ID_PATTERN = re.compile(r"^(((SR|ER|DR)[APRSX])|(SAM(N|EA|D))|(PRJ(NA|EB|DB))|(GS[EM]))(\d+)$")


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: check_ids.py <FILE_IN> <FILE_OUT>")
    file_in, file_out = sys.argv[1], sys.argv[2]

    total = 0
    ids = []
    seen = set()
    no_match = []
    with open(file_in, "r") as fin:
        for line in fin:
            db_id = line.strip()
            if not db_id:
                continue
            total += 1
            if ID_PATTERN.match(db_id):
                if db_id not in seen:
                    seen.add(db_id)
                    ids.append(db_id)
            else:
                no_match.append(db_id)

    if total == 0:
        sys.exit(
            "Ids provided via --input not recognised please make sure they are "
            "either SRA / ENA / GEO / DDBJ ids!"
        )
    if no_match:
        sys.exit(
            "Mixture of ids provided via --input: {}\n"
            "Please provide either SRA / ENA / GEO / DDBJ ids!".format(", ".join(no_match))
        )

    with open(file_out, "w") as fout:
        fout.write("\n".join(ids) + "\n")


if __name__ == "__main__":
    sys.exit(main())
