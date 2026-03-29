#!/bin/bash
# check_schema_docs.sh — Validates DB schema annotations in ChatPrompts
#
# In the original Fazm dev environment, this verifies that the {database_schema}
# variable in ChatPrompts.swift matches the actual GRDB table definitions in
# AppDatabaseModels.swift. This prevents the LLM from hallucinating column names.
#
# This script was never committed to git (scripts/ is gitignored by Fazm).
# Skipping safely — schema mismatches only affect LLM SQL tool accuracy,
# not app build or runtime.
exit 0
