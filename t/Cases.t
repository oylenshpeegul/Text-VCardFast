# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Text-VCardFast.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;
use FindBin qw($Bin);
use Test::More;
use JSON::XS;

BEGIN { use_ok('Text::VCardFast') };

my @tests;
if (opendir(DH, "$Bin/cases")) {
    while (my $item = readdir(DH)) {
	next unless $item =~ m/^(.*)\.vcf$/;
	push @tests, $1;
    }
    closedir(DH);
}

my $numtests = @tests;
plan tests => ($numtests * 8) + 2;

ok($numtests, "we have $numtests cards to test");

foreach my $test (@tests) {
    my $vdata = getfile("$Bin/cases/$test.vcf");
    ok($vdata, "data in $test.vcf");
    my $chash = eval { Text::VCardFast::vcard2hash_c($vdata, { multival => ['adr','org','n'] }) };
    ok($chash, "parsed VCARD in $test.vcf with C ($@)");
    my $phash = eval { Text::VCardFast::vcard2hash_pp($vdata, { multival => ['adr','org','n'] }) };
    ok($phash, "parsed VCARD in $test.vcf with pureperl ($@)");

    unless (is_deeply($phash, $chash, "contents of $test.vcf match from C and pureperl")) {
	use Data::Dumper;
	die Dumper($phash, $chash);
    }

    my $jdata = getfile("$Bin/cases/$test.json");
    unless (ok($jdata, "data in $test.json")) {
	my $coder = JSON::XS->new->utf8->pretty;
	die $coder->encode($chash);
    }
    my $jhash = eval { decode_json($jdata) };
    ok($jhash, "valid JSON in $test.json ($@)");

    unless (is_deeply($jhash, $chash, "contents of $test.vcf match $test.json")) {
	my $coder = JSON::XS->new->utf8->pretty;
	die "$jdata\n\n\n" . $coder->encode($chash);
    }

    my $data = Text::VCardFast::hash2vcard($chash);
    # hash2vcard clobbers
    my $newchash = eval { Text::VCardFast::vcard2hash_c($vdata, { multival => ['adr','org','n'] }) };
    my $rehash = Text::VCardFast::vcard2hash_c($data, { multival => ['adr','org','n'] });

    unless (is_deeply($rehash, $newchash, "generated and reparsed data matches for $test")) {
	use Data::Dumper;
	die Dumper($rehash, $newchash, $vdata, $data);
    }
}

sub getfile {
    my $file = shift;
    open(FH, "<$file") or return;
    local $/ = undef;
    my $res = <FH>;
    close(FH);
    return $res;
}

