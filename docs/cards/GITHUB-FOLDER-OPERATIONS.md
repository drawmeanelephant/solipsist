# GitHub working-copy operations — #310

Issue: https://github.com/drawmeanelephant/solipsist/issues/310

## Scope

Local and GitHub sources use the existing `PlayFolderSource` contract
for Compose and manual Boris commands. Preserve source/file identity,
bookmark access, workspace-relative outputs, and source-bound watches
and save-triggered validation.

An unavailable or unreadable working folder surfaces a clear error.
Local editing/building never implies commit, push, PR authoring, or
publishing. Those remain explicit remote verbs.

## Paths and gate

`Sources/Workspace/Source.swift`, `Sources/Compose/`,
`Sources/App/Coordinator.swift`, `Tests/ContractTests/`, `Tests/Native/`,
and Help.

Run regressions for both providers, missing folders, invalid bookmarks,
failed reads, dirty switches, manual Plan/Validate/Build, and bound-save
validation. Native checks use temporary working copies and a stub
engine, without authentication or remote mutation.
