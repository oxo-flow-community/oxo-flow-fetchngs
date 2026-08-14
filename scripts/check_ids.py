#!/usr/bin/env python3
"""oxo-flow port of the nf-core/fetchngs input-id validation.

Ports the `isSraId` / id-channel logic of the PIPELINE_INITIALISATION
subworkflow (nf-core/fetchngs 1.12.0): validates every identifier in FILE_IN
against the upstream SRA / ENA / DDBJ / GEO accession regex, then writes the
stripped, deduplicated ids (upstream `Channel.from(...).splitCsv(...).unique()`)
to FILE_OUT.

Usage: check_ids.py <FILE_IN> <FILE_OUT>
"""

import re
import sys

# Regex from `def isSraId(input)` in subworkflows/local/utils_nfcore_fetchngs_pipeline/main.nf
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
