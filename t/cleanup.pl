#!/usr/bin/env perl

# This is a simple cleanup script to be 
# called after testing to avoid leaving a mess 
# - Shreyas Cholia 11/30/2012
use Bio::KBase::workspaceService::Impl;
my $impl = Bio::KBase::workspaceService::Impl->new();
#Deleting test objects
$impl->_clearAllWorkspaces();
$impl->_clearAllWorkspaceObjects();
$impl->_clearAllWorkspaceUsers();
$impl->_clearAllWorkspaceDataObjects();

print "Clean up complete"