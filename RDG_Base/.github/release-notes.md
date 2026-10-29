<!-- Template for the release notes. Fill in every section before publishing the draft. -->

# RDG {{VERSION}}

## Changes

-

## Breaking changes

None.

## Upgrade checklist

- **Rerun bootstrap stage 2** (new tenant grants): no
- **New or changed settings** in the settings file: none
- **Data format changes**: none (the previous version can still read the data)

## Install or upgrade

Set `rdgVersion: '{{VERSION}}'` in your `azure-pipelines.yml` and run the pipeline.

The bundle `rdg-{{VERSION}}.zip` has a build provenance attestation:
`gh attestation verify rdg-{{VERSION}}.zip --repo <owner>/rdg`
