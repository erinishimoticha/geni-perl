#!/usr/bin/perl

print "# BEGIN TEST ############################################################\n";

use WWW::Geni;
print "WWW::Geni loaded.\n";
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

print "Using Geni.pm version $WWW::Geni::VERSION", "\n";

my $geni;
unless ($geni = new WWW::Geni({
	'user' => 'erin@thespicelands.com',
	'pass' => $ARGV[0],
	'client_id' => $ARGV[1]
})) {
	print "Not logged in. $WWW::Geni::errstr\n"; exit(0);
}
print "Logged in with token ", $geni->{access_token}, ".\n";

do_tree_conflicts();

sub do_tree_conflicts(){
	my $conflictlist = $geni->tree_conflicts()
		or die "Couldn't get tree conflicts: $WWW::Geni::errstr\n";
	my $count = 0;
	while(my $conflict = $conflictlist->get_next()){
		$count++;
		my $focus = $conflict->profile();
		print "# new ", $conflict->type(), " conflict #####################\n";
		print "Focus:", $focus->first_name(), " ", $focus->middle_name(), " ",
			$focus->last_name(), "\n";
		while (my $memberlist = $conflict->fetch_list()) {
			print "Got ", $memberlist->{type}, "\n";
			while (my $member = $memberlist->get_next()) {
				print sprintf("\t%s: %s %s %s\n", $memberlist->{type},
					$member->first_name(), $member->middle_name(),
					$member->last_name());
			}
		}
	}
}
