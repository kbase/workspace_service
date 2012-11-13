#!/usr/bin/env perl 
# A simple script that removes the bearer token at
# $ENV{HOME}/.kbase_auth
unlink "$ENV{HOME}/.kbase_auth";
