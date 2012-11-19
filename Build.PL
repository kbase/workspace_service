#!/usr/bin/env perl
use Module::Build;
Module::Build->new(
    module_name => 'Bio::KBase::workspaceService',
    license     => 'perl',
    requires => {
        'Text::Table'               => 0,
        'Data::UUID'                => 0,
        'Getopt::Long::Descriptive' => 0,
        'Term::ReadKey'             => 0,
    },
    dist_abstract => 'Implementation, client libraries and CLI client for workspace services',
)->create_build_script;
