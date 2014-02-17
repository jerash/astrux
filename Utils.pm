#!/usr/bin/perl

package Utils;

use strict;
use warnings;

#replace any non alphanumeric character with % followed by 2char ascii code (nonmixer mimic)
sub encode_my_ascii {
	my $characters = shift;
	$characters =~ s/([^\w!-])/sprintf("%%%X",ord($1))/eg;
	return $characters;
}
#replace any % followed by 2char ascii code by its ascii character (nonmixer mimic)
sub decode_my_ascii {
	my $characters = shift;
	$characters =~ s/%([0-9A-F][0-9A-F])/chr(hex($1))/eg;
	return $characters;
}
#replace any non space character with _
sub underscore_my_spaces {
	my $characters = shift;
	$characters =~ s/\s/_/g;
	return $characters;
}

use MIME::Base64;

sub encode_my_base64 {
	my $characters = shift;
	return encode_base64($characters);
}
sub decode_my_base64 {
	my $characters = shift;
	return decode_base64($characters);
}

1;