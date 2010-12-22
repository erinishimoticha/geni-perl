package Geni;

use 5.001;
use strict;
use warnings;
use HTTP::Cookies;
use HTTP::Response;
use LWP::UserAgent;
use vars qw($VERSION $errstr);

$VERSION = '0.01';

# sub color {
# $_[0]->{Color}
# }
# sub set_color {
# $_[0]->{Color} = $_[1];
# }

# my $bad = bless { Name => "Evil", Color => "black" }, Sheep;
BEGIN {
	sub _profile_get_tree_conflicts_url { "https://www.geni.com/api/profile/tree-conflicts"; }
	sub _profile_get_immediate_family_url { "https://www.geni.com/api/profile/immediate-family"; }
	sub _profile_get_merges_url { "https://www.geni.com/api/profile/merges"; }
	sub _profile_get_data_conflicts_url { "https://www.geni.com/api/profile/data-conflicts"; }
	sub _profile_get_tree_matches_url { "https://www.geni.com/api/profile/tree-matches"; }

	sub _profile_do_merge_url($$) { "https://www.geni.com/api/profile-$_[0]/merge/profile-$_[1]"; }

	sub _project_get_collaborators_url { "https://www.geni.com/api/project-6/collaborators"; }
	sub _project_get_profiles_url { "https://www.geni.com/api/project-6/profiles"; }
	sub _project_get_followers_url { "https://www.geni.com/api/project-6/followers"; }
}

sub new {
	my $class = shift;
	my $self = {
		user => shift,
		pass => shift,
		only_ids => $_{only_ids}
	};
	if (!$self->{user} || !$self->{pass}){
		$Geni::errstr = "Username and password are required parameters to Geni::new().";
		return 0;
	}else{
		bless $self, $class;
		return $self;
	}
}

sub username {
	my $self = shift;
	return $self->{user};
}

sub login {
	my $self = shift;
	$self->{ua} = LWP::UserAgent->new();
	$self->{ua}->cookie_jar(HTTP::Cookies->new());
	my $res = $self->{ua}->post("https://www.geni.com/login/in?username=" . $self->{user} . "&password=" . $self->{pass});
	return $res->content =~ /redirected/;
}

sub get_tree_conflicts {
	my $self = shift;
	my $res = $self->{ua}->get($self->_profile_get_tree_conflicts_url());
	return $res->is_success ? $res->decoded_content : 0;
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Geni - Perl extension for Geni.com

=head1 SYNOPSIS

	use Geni;
	my $geni = new Geni;
	my @conflicts = $geni->conflicts();

=head1 DESCRIPTION

Use this module to manipulate Geni profiles.

=head1 METHODS

=head2 $geni->new( $username, $password )
=cut

=head2 $geni->login()
=cut

=head2 $geni->username()

Returns Geni username.

=cut

=head1 SEEALSO

GitHub

=head1 AUTHOR

Erin Spiceland <lt>erin@thespicelands.com<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Erin Spiceland

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
