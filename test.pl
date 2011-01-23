#!/usr/bin/perl

print "# BEGIN TEST ############################################################\n";
use Geni;

my $geni = new Geni('erin@thespicelands.com', 'msjeep') or print $Geni::errstr, "\n";
print "Using Geni.pm version $Geni::VERSION", "\n";
$geni->login() or print "Login failed!", "\n";
my $list = $geni->get_tree_conflicts();
my $count = 0;
while(my $conflict = $list->get_next()){
	$count++;
	print "$count. ", $conflict->get_type(), " :: ", $conflict->get_profile(), "\n";
}
