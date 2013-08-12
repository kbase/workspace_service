#!/bin/sh
# Remove \CR endings if they are present
if [ `command -v dos2unix 2>/dev/null` ]; then
    dos2unix workspaceService.spec
fi
# Compile workspaceService
db_base=Bio::KBase::workspaceService
compile_typespec                \
    -impl $db_base::Impl        \
    -service $db_base::Service  \
    -psgi workspaceService.psgi      \
    -client $db_base::Client \
    -js workspaceService     \
    -py workspaceService     \
    workspaceService.spec lib


