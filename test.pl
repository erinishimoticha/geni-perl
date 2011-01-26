#!/usr/bin/perl

print "# BEGIN TEST ############################################################\n";
use Geni;
print "Using Geni.pm version $Geni::VERSION", "\n";

my $geni = new Geni('erin@thespicelands.com', $ARGV[0]) or print $Geni::errstr, "\n";

do_tree_conflicts();

sub do_tree_conflicts(){
	my $conflictlist = $geni->get_tree_conflicts() or print "$Geni::errstr\n" && die;
	my $count = 0;
	while(my $conflict = $conflictlist->get_next()){
			$count++;
			print "# NEW CONFLICT ###############################\n", 
				"$count. type: ", $conflict->get_type(), "\n\t",
				"profile: ", $conflict->get_profile(), "\n\t",
				"actor: ", $conflict->get_actor(), "\n\t",
				"page_num: ", $conflict->get_page_num(), "\n\t",
				"managers: ", $conflict->get_managers(), "\n";
		while (my $memberlist = $conflict->fetch_conflict_list()) {
			print "Processing the ", $memberlist->{type}, "\n";
			while (my $member = $memberlist->get_next()) {
				print $memberlist->{type}, ": ", $member->{first_name}, 
				" ", $member->{middle_name}, " ", $member->{last_name}, "\n";
			}
		}
	}
}
