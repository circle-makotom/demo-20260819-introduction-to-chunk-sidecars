# Demo 1

Introduce a new property `defunct_at` in Publisher, which represents whether the relevant publisher is defunct, and when it went defunct if it is. Update controllers and views accordingly as well.

Follow /validate-via-sidecars for the work, as well as .claude/CLAUDE.md for more specific operational guidelines.

# Demo 2

We have a plan to make a record of digests of objects whenever the objects (like Books) are created/updated, for easier look up of versions.

Pick up 4 - 5 hash functions and write a benchmarking script for each. For each benchmarking pattern - such as each combination of hash functions and message lengths, spin up its dedicated sidecar, use /dev/urandom as the source of input, and run the benchmark for 60 sec at least to obtain normalized throughput. Use /offload-tasks-to-sidecars for benchmarking and run benchmarks in parallel. See .claude/CLAUDE.md for more specific operational guidelines.

Based on the results I decide the hash function to be used in production.

# Demo 3

There is a list of repositories at ~/repos.txt. For each of them, attempt to get the latest pipeline run on CircleCI by calling CircleCI's API directly.

The expected output is an aggregated TSV file containing A) repo slug, B) the last pipeline UUID, C) the slug of the user triggered the pipeline, and D) the timestamp of the last pipeline. If the last pipeline couldn't be found, put the string literal "N/A" for columns B to D.

Use /offload-tasks-to-sidecars to divide-and-conquer the task - consider spinning up 10 sidecars. See .claude/CLAUDE.md (at the project level, adjacent to this file with this prompt, not the child of ~/) for more specific operational guidelines.
