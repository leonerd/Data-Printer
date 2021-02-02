use strict;
use warnings;
use Test::More tests => 34;
use Data::Printer::Config;
use Data::Printer::Object;
use File::Spec;

my @warnings;
{ no warnings 'redefine';
    *Data::Printer::Common::_warn = sub { push @warnings, $_[1] };
}

my $profile = Data::Printer::Config::_expand_profile({ profile => 'Invalid;Name!' });

is ref $profile, 'HASH', 'profile expanded into hash';
is_deeply $profile, {}, 'bogus profile not loaded';
is @warnings, 1, 'invalid profile triggers warning';
like $warnings[0], qr/invalid profile name/, 'right message on invalid profile';

@warnings = ();
$profile = Data::Printer::Config::_expand_profile({ colored => 1, profile => 'Invalid;Name!' });
is ref $profile, 'HASH', 'profile expanded into hash';
is_deeply $profile, { colored => 1 }, 'options preserved after bogus profile not loaded';
is @warnings, 1, 'invalid profile triggers warning (2)';
like $warnings[0], qr/invalid profile name/, 'right message on invalid profile (2)';

@warnings = ();
$profile = Data::Printer::Config::_expand_profile({ colored => 1, profile => 'BogusProfile' });
is ref $profile, 'HASH', '(bad) profile expanded into hash';
is_deeply $profile, { colored => 1 }, 'options preserved after bogus profile not loaded (3)';
is @warnings, 1, 'invalid profile triggers warning (3)';
like $warnings[0], qr/unable to load profile/, 'right message on invalid profile (3)';

@warnings = ();
$profile = Data::Printer::Config::_expand_profile({ profile => 'Dumper' });
is @warnings, 0, 'no warnings after proper profile loaded';
is $profile->{name}, '$VAR1', 'profile loaded ok';
is $profile->{colored}, 0, 'profile color set';

@warnings = ();
$profile = Data::Printer::Config::_expand_profile({ colored => 1, profile => 'Dumper' });
is @warnings, 0, 'no warnings after proper profile loaded with extra options';
is $profile->{name}, '$VAR1', 'profile with extra options loaded ok';
is $profile->{colored}, 1, 'profile color properly overriden';

@warnings = ();
$profile = Data::Printer::Config::_expand_profile({ profile => 'Dumper' });
is @warnings, 0, 'dumper profile loaded';

my $ddp = Data::Printer::Object->new($profile);

my $lvalue = \substr("abc", 2);
my $file = File::Spec->catfile(
    Data::Printer::Config::_my_home('testing'), 'test_file.dat'
);
open my $glob, '>', $file or skip "error opening '$file': $!", 1;

format TEST =
.
my $format = *TEST{FORMAT};

my $vstring = v1.2.3;

my $scalar = 1;

my $regex = qr/^2\s\\\d+$/i;

my $target = {
    foo => [undef, $scalar, 'two', $regex, $glob, $lvalue, \321, $vstring, $format, sub {}, bless(\$scalar, 'TestClass')]
};
push @{$target->{foo}}, \$target->{foo}[0]; # circular ref check #1
push @{$target->{foo}}, $target->{foo}[6]; # circular ref check #2


@warnings = ();
my $output = $ddp->parse($target);
is @warnings, 2, 'dumper profile is unable to parse 2 types of ref';
like $warnings[0], qr/cannot handle ref type 10/, 'dumper warning on lvalue';
like $warnings[1], qr/cannot handle ref type 14/, 'dumper warning on format';
my $expected = <<'EODUMPER';
$VAR1 = {
          'foo' => [
                    undef,
                    1,
                    'two',
                    qr/^2\s\\\d+$/i,
                    \*{'::$glob'},
                    ,
                    \ 321,
                    v1.2.3,
                    ,
                    sub { "DUMMY" },
                    bless( do{\(my $o = 1)}, 'TestClass' ),
                    \ $VAR1->{'foo'}[0],
                    \ $VAR1->{'foo'}[6]
          ]
};
EODUMPER
chop $expected; # remove last newline

is $output, $expected, 'proper result in dumper profile';

@warnings = ();
$profile = Data::Printer::Config::_expand_profile({ profile => 'JSON' });
is @warnings, 0, 'json profile loaded';

$ddp = Data::Printer::Object->new($profile);

$output = $ddp->parse($target);
is @warnings, 10, 'json profile is unable to parse 2 types of ref';
like $warnings[0], qr/regular expression cast to string \(flags removed\)/, 'json warning on regexes';
like $warnings[1], qr/json cannot express globs/, 'json warnings on globs';
like $warnings[2], qr/json cannot express references to scalars. Cast to non-reference/, 'json warning on refs';
like $warnings[3], qr/json cannot express vstrings/, 'json warnings on vstring';
like $warnings[4], qr/json cannot express subroutines. Cast to string/, 'json warning on functions';
like $warnings[5], qr/json cannot express blessed objects/, 'json warning on objects';

like $warnings[6], qr/json cannot express references to scalars. /, 'json warning on refs';
like $warnings[7], qr/json cannot express circular references./, 'json warning on circular refs';

$expected = <<'EOJSON';
{
  "foo": [
    null,
    1,
    "two",
    "/^2\s\\\d+$/i",
    ,
    "c",
    321,
    "v1.2.3",
    "FORMAT",
    "sub { ... }",
    1,
    "var{"foo"}[0]",
    "var{"foo"}[6]"
  ]
}
EOJSON
chop $expected; # remove last newline
is $output, $expected, 'proper result in json profile';
