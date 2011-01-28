#!/usr/bin/perl

print "# BEGIN TEST ############################################################\n";

use Geni;
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

print "Using Geni.pm version $Geni::VERSION", "\n";

my $geni = new Geni('erin@thespicelands.com', $ARGV[0]) or die $Geni::errstr, "\n";

do_tree_conflicts();

sub do_tree_conflicts(){
	my $conflictlist = $geni->get_tree_conflicts() or die "$Geni::errstr\n";
	my $count = 0;
	while(my $conflict = $conflictlist->get_next()){
		$count++;
		my $focus = $conflict->get_profile();
		print "# new ", $conflict->get_type(), " conflict ############################\n"; 
		print "Focus:", $focus->get_first_name(), " ", $focus->get_middle_name(), " ",
			$focus->get_last_name(), "\n";
		while (my $memberlist = $conflict->fetch_list()) {
			print "Got ", $memberlist->{type}, "\n";
			while (my $member = $memberlist->get_next()) {
				print sprintf("\t%s: %s %s %s\n", $memberlist->{type}, $member->get_first_name(), 
				$member->get_middle_name(), $member->get_last_name());
			}
		}
	}
}
