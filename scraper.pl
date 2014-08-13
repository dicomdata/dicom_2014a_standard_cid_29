#!/usr/bin/env perl
# Copyright 2014 Michal Špaček <tupinek@gmail.com>

package Dicom::Handler;

# Pragmas.
use strict;
use warnings;

# Modules.
use English;

# Constructor.
sub new {
	my ($type, %params) = @_;
	return bless {
		%params,
		'table_flag' => 0,
		'td_index' => -1,
		'td' => ['', '', ''],
		'td_ok' => 0,
		'tr_index' => 0,
	}, $type;
}

# Start element.
sub start_element {
	my ($self, $element) = @_;
	if (exists $element->{'Attributes'}
		&& exists $element->{'Attributes'}->{'{}label'}
		&& $element->{'Attributes'}->{'{}label'}->{'Value'} eq 'CID 29') {

		$self->{'table_flag'} = 1;
	}
	if (! $self->{'table_flag'}) {
		return;
	}

	# Right td.
	if (! $self->{'td_ok'}) {
		return;
	}
	if ($element->{'Name'} eq 'td') {
		$self->{'td_index'}++;
	}
	return;
}

# End element.
sub end_element {
	my ($self, $element) = @_;
	if (! $self->{'table_flag'}) {
		return;
	}
	if ($element->{'Name'} eq 'table') {
		$self->{'table_flag'} = 0;
	}

	# Right tr element.
	if ($element->{'Name'} eq 'tr') {
		if ($self->{'tr_index'} == 0) {
			$self->{'tr_index'} = 1;
			$self->{'td_ok'} = 1;
			return;
		}
		my ($code_scheme_designator, $code_value, $code_meaning)
			= @{$self->{'td'}};
		my $ret_ar = eval {
			$self->{'dt'}->execute('SELECT COUNT(*) FROM data '.
				'WHERE Code_value = ?', $code_value);
		};
		if ($EVAL_ERROR || ! @{$ret_ar}
			|| ! exists $ret_ar->[0]->{'count(*)'}
			|| ! defined $ret_ar->[0]->{'count(*)'}
			|| $ret_ar->[0]->{'count(*)'} == 0) {

			print "$code_value: $code_meaning\n";
			$self->{'dt'}->insert({
				'Code_scheme_designator' => $code_scheme_designator,
				'Code_value' => $code_value,
				'Code_meaning' => $code_meaning,
			});
		}
		$self->{'dt'}->create_index(['Code_Value'], 'data', 1, 1);
		$self->{'td'} = ['', '', ''];
		$self->{'td_index'} = -1;
	}
	return;
}

# Characters.
sub characters {
	my ($self, $characters) = @_;
	if (! $self->{'table_flag'}) {
		return;
	}

	# Skip blank data.
	if ($characters->{'Data'} =~ m/^\s*$/ms) {
		return;
	}

	# Right td.
	if (! $self->{'td_ok'}) {
		return;
	}
	$self->{'td'}->[$self->{'td_index'}] .= $characters->{'Data'};
	return;
}

package main;

# Pragmas.
use strict;
use warnings;

# Modules.
use Database::DumpTruck;
use Encode qw(decode_utf8 encode_utf8);
use English;
use File::Temp qw(tempfile);
use LWP::UserAgent;
use URI;
use XML::SAX::Expat;

# Don't buffer.
$OUTPUT_AUTOFLUSH = 1;

# URI of service.
my $base_uri = URI->new('ftp://medical.nema.org/medical/dicom/2014a/source/docbook/part16/part16.xml');

# Open a database handle.
my $dt = Database::DumpTruck->new({
	'dbname' => 'data.sqlite',
	'table' => 'data',
});

# Create a user agent object.
my $ua = LWP::UserAgent->new(
	'agent' => 'Mozilla/5.0',
);

# Get base root.
print 'Page: '.$base_uri->as_string."\n";
my $xml_file = get_file($base_uri);
my $h = Dicom::Handler->new(
	'dt' => $dt,
);
my $p = XML::SAX::Expat->new('Handler' => $h);
$p->parse_file($xml_file);
unlink $xml_file;

# Get file
sub get_file {
	my $uri = shift;
	my (undef, $tempfile) = tempfile();
	my $get = $ua->get($uri->as_string,
		':content_file' => $tempfile,
	);
	if ($get->is_success) {
		return $tempfile;
	} else {
		die "Cannot GET '".$uri->as_string." page.";
	}
}
