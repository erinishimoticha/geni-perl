#!/usr/bin/perl

use Geni;

my $geni = new Geni('erin@thespicelands.com', 'msjeep') or print $Geni::errstr, "\n";
print "Using Geni.pm version $Geni::VERSION", "\n";
$geni->login() or print "Login failed!", "\n";
print $geni->tree_conflicts(), "\n";
